//! Foreground PC controls for a title window (`VICTORY_PC_CONTROLS=1`).
//! Raw mouse motion drives the virtual right stick; `F5` switches between
//! On-Foot and Driving layouts; `F6` (or `Esc` while captured) releases or
//! recaptures the mouse cursor. Switching windows releases the cursor cleanly.
//!
//! Native keyboard and mouse (`VICTORY_NATIVE_INPUT=1`, [`super::native`])
//! takes the mouse the same way, but keys stay the title's: `Esc` pauses and
//! keeps the mouse, `Left Alt` or a Windows key lets it go, a click takes it
//! back. [`read_native`] hands the buttons, wheel and raw motion over.

use std::ptr::{null, null_mut};
use std::sync::atomic::{AtomicBool, Ordering::Relaxed};
use std::sync::{LazyLock, Mutex, OnceLock};
use std::time::{Duration, Instant};

use windows_sys::Win32::Foundation::{HWND, LPARAM, LRESULT, POINT, RECT, WPARAM};
use windows_sys::Win32::Graphics::Gdi::ClientToScreen;
use windows_sys::Win32::UI::Input::KeyboardAndMouse::{
    GetAsyncKeyState, VK_F5, VK_F6, VK_LBUTTON, VK_MBUTTON, VK_RBUTTON, VK_XBUTTON1, VK_XBUTTON2,
};
use windows_sys::Win32::UI::Input::{
    GetRawInputData, MOUSE_MOVE_ABSOLUTE, MOUSE_VIRTUAL_DESKTOP, RAWINPUT, RAWINPUTDEVICE,
    RAWINPUTHEADER, RID_INPUT, RIM_TYPEMOUSE, RegisterRawInputDevices,
};
use windows_sys::Win32::UI::WindowsAndMessaging as wm;
use windows_sys::core::w;

use super::native::{self, FrameLook, NativeMouse};
use super::{
    KeyState, LEFT_SHOULDER, PadState, RIGHT_SHOULDER, RIGHT_STICK, lock, merged, pc_keyboard,
};

/// `VICTORY_PC_CONTROLS=1`: the keyboard and mouse drive the stand-in pad
/// by the PC layout ([`pc_keyboard`]).
pub(super) fn pc_controls() -> bool {
    static ENABLED: OnceLock<bool> = OnceLock::new();
    *ENABLED.get_or_init(|| std::env::var_os("VICTORY_PC_CONTROLS").is_some_and(|s| s == "1"))
}

/// The title's window takes the mouse: PC controls or native input.
pub(super) fn enabled() -> bool {
    pc_controls() || native::enabled()
}

/// Mouse look sensitivity multiplier (`VICTORY_MOUSE_SENSITIVITY`, or
/// `VICTORY_MOUSE_SENS`; default `1.0`).
pub(super) fn sensitivity() -> f32 {
    static SCALE: LazyLock<f32> = LazyLock::new(|| {
        std::env::var("VICTORY_MOUSE_SENSITIVITY")
            .or_else(|_| std::env::var("VICTORY_MOUSE_SENS"))
            .ok()
            .and_then(|s| s.trim().parse::<f32>().ok())
            .filter(|v| v.is_finite() && *v > 0.0)
            .unwrap_or(1.0)
    });
    *SCALE
}

/// Invert vertical mouse look (`VICTORY_MOUSE_INVERT_Y=1`).
fn invert_y() -> bool {
    static INVERT: LazyLock<bool> =
        LazyLock::new(|| std::env::var_os("VICTORY_MOUSE_INVERT_Y").is_some_and(|v| v == "1"));
    *INVERT
}

// A small averaging window bridges the mouse report rate and the game's
// frame rate. A stopped mouse returns completely to neutral.
#[derive(Default)]
struct Motion {
    pending: [f32; 2],
    velocity: [f32; 2],
    sampled: Option<Instant>,
    moved: Option<Instant>,
}

impl Motion {
    fn add(&mut self, dx: f32, dy: f32, now: Instant) {
        if dx != 0.0 || dy != 0.0 {
            self.pending[0] += dx;
            self.pending[1] -= dy;
            self.moved = Some(now);
        }
    }

    fn stick(&mut self, now: Instant, sens: f32, invert: bool) -> [f32; 2] {
        let dt = self
            .sampled
            .replace(now)
            .map_or(0.008, |t| now.duration_since(t).as_secs_f32())
            .clamp(0.001, 0.060);
        let mut deltas = std::mem::take(&mut self.pending);
        if invert {
            deltas[1] = -deltas[1];
        }
        deltas[0] *= sens;
        deltas[1] *= sens;
        if self
            .moved
            .is_none_or(|t| now.duration_since(t) >= Duration::from_millis(60))
        {
            self.velocity = [0.0; 2];
            return self.velocity;
        }
        let blend = 1.0 - (-dt / 0.022).exp();
        for (v, delta) in self.velocity.iter_mut().zip(deltas) {
            *v += blend * (delta / (dt * 1300.0) - *v);
        }
        let [x, y] = self.velocity;
        let len = x.hypot(y);
        if len < 0.012 {
            return [0.0; 2];
        }
        // Give small movements enough range to cross the game's stick dead zone.
        let gain = (0.19 + 0.81 * len.min(1.0)) / len;
        [x * gain, y * gain]
    }
}

#[derive(Default)]
struct Capture {
    window: usize,
    clip: Option<RECT>,
    motion: Motion,
    absolute: Option<(usize, i32, i32)>,
    blocked: u8,
    last_flags: usize,
    /// Native input: camera look, raw motion (down positive) and wheel
    /// notches (up positive) since the last [`read_native`].
    look: FrameLook,
    raw: [f32; 2],
    wheel: i32,
}

static CAPTURE: LazyLock<Mutex<Capture>> = LazyLock::new(|| Mutex::new(Capture::default()));
static DRIVING: AtomicBool = AtomicBool::new(false);
static WANTED: AtomicBool = AtomicBool::new(true);
static RAW: OnceLock<bool> = OnceLock::new();

/// Whether `F` (enter / exit vehicle) also switches the W/S layout between
/// on foot and driving: on unless `VICTORY_AUTO_DRIVE=0`.
fn auto_drive() -> bool {
    static ON: OnceLock<bool> = OnceLock::new();
    *ON.get_or_init(|| std::env::var("VICTORY_AUTO_DRIVE").map_or(true, |v| v.trim() != "0"))
}

pub(in crate::modules) fn install(hwnd: HWND) {
    if !enabled() {
        return;
    }
    // SAFETY: window creation calls us with a live title window. A child
    // cannot own pointer capture or advertise the desktop controller profile.
    unsafe {
        if wm::GetAncestor(hwnd, wm::GA_ROOT) != hwnd {
            return;
        }
        wm::SetPropW(hwnd, w!("victory.pc_controls"), 1usize as _);
    }
    RAW.get_or_init(|| {
        // Foreground delivery to the window with focus. Keep ordinary
        // window and keyboard messages available to the title and OS.
        let mouse = RAWINPUTDEVICE {
            usUsagePage: 1,
            usUsage: 2,
            dwFlags: 0,
            hwndTarget: null_mut(),
        };
        // SAFETY: one device descriptor of the advertised size.
        let ok =
            unsafe { RegisterRawInputDevices(&mouse, 1, size_of::<RAWINPUTDEVICE>() as u32) } != 0;
        if !ok {
            tracing::warn!("could not register foreground raw mouse input");
        }
        ok
    });
    acquire(hwnd);
}

/// Buttons held: bits left, right, middle, 4, 5.
fn mouse_buttons() -> u8 {
    // SAFETY: queries of physical mouse button state.
    let down = |vk: u16| unsafe { GetAsyncKeyState(vk.into()) } < 0;
    [VK_LBUTTON, VK_RBUTTON, VK_MBUTTON, VK_XBUTTON1, VK_XBUTTON2]
        .into_iter()
        .enumerate()
        .fold(0, |bits, (i, vk)| bits | (u8::from(down(vk)) << i))
}

fn clip_to_client(hwnd: HWND) -> Option<RECT> {
    let mut rect = RECT::default();
    let mut start = POINT::default();
    // SAFETY: a live title window; the rectangles and points are writable.
    unsafe {
        if wm::GetClientRect(hwnd, &mut rect) == 0 || rect.right <= 1 || rect.bottom <= 1 {
            return None;
        }
        let mut end = POINT {
            x: rect.right,
            y: rect.bottom,
        };
        if ClientToScreen(hwnd, &mut start) == 0 || ClientToScreen(hwnd, &mut end) == 0 {
            return None;
        }
        let bounds = RECT {
            left: start.x,
            top: start.y,
            right: end.x,
            bottom: end.y,
        };
        (wm::ClipCursor(&bounds) != 0).then_some(bounds)
    }
}

fn acquire(hwnd: HWND) {
    if !WANTED.load(Relaxed) || RAW.get() != Some(&true) {
        return;
    }
    // SAFETY: queries of the foreground and the supplied window.
    if unsafe {
        wm::GetForegroundWindow() != hwnd
            || wm::GetAncestor(hwnd, wm::GA_ROOT) != hwnd
            || wm::IsIconic(hwnd) != 0
    } {
        return;
    }
    let mut state = lock(&CAPTURE);
    if state.window == hwnd as usize {
        return;
    }
    let Some(clip) = clip_to_client(hwnd) else {
        return;
    };
    *state = Capture {
        window: hwnd as usize,
        clip: Some(clip),
        blocked: mouse_buttons(),
        ..Capture::default()
    };
    // SAFETY: an integer flag on our own window and a temporary invisible cursor.
    unsafe {
        wm::SetPropW(hwnd, w!("victory.mouse_look"), 1usize as _);
        if DRIVING.load(Relaxed) {
            wm::SetPropW(hwnd, w!("victory.driving_keys"), 1usize as _);
        }
        wm::SetCursor(null_mut());
    }
}

fn release(hwnd: HWND) {
    let mut state = lock(&CAPTURE);
    if state.window != hwnd as usize || hwnd.is_null() {
        return;
    }
    // A newly focused program may already have claimed the desktop clip.
    // SAFETY: the rectangle is writable and we clear only our own clip/properties.
    unsafe {
        let mut current = RECT::default();
        if let Some(ours) = state.clip
            && wm::GetClipCursor(&mut current) != 0
            && (current.left, current.top, current.right, current.bottom)
                == (ours.left, ours.top, ours.right, ours.bottom)
        {
            wm::ClipCursor(null());
        }
        wm::RemovePropW(hwnd, w!("victory.mouse_look"));
        wm::RemovePropW(hwnd, w!("victory.pc_buttons"));
        if wm::GetForegroundWindow() == hwnd {
            wm::SetCursor(wm::LoadCursorW(null_mut(), wm::IDC_ARROW));
        }
    }
    *state = Capture::default();
}

fn raw_motion(hwnd: HWND, handle: LPARAM) -> bool {
    let mut state = lock(&CAPTURE);
    if state.window != hwnd as usize {
        return false;
    }
    let mut packet = RAWINPUT::default();
    let mut size = size_of::<RAWINPUT>() as u32;
    // SAFETY: WM_INPUT supplied the handle, and packet is a fixed-size, aligned mouse buffer.
    let read = unsafe {
        GetRawInputData(
            handle as _,
            RID_INPUT,
            (&raw mut packet).cast(),
            &mut size,
            size_of::<RAWINPUTHEADER>() as u32,
        )
    };
    if read == u32::MAX
        || read
            < (size_of::<RAWINPUTHEADER>() + size_of::<windows_sys::Win32::UI::Input::RAWMOUSE>())
                as u32
        || packet.header.dwType != RIM_TYPEMOUSE
    {
        return false;
    }
    // SAFETY: the header selects the mouse member.
    let mouse = unsafe { packet.data.mouse };
    const RI_MOUSE_WHEEL: u16 = 0x0400;
    // SAFETY: plain integers in both members of the union.
    let (flags, data) = unsafe {
        (
            mouse.Anonymous.Anonymous.usButtonFlags,
            mouse.Anonymous.Anonymous.usButtonData,
        )
    };
    if flags & RI_MOUSE_WHEEL != 0 {
        let delta = data as i16;
        // A notch is 120; a free-spinning wheel may report less.
        state.wheel += if delta.abs() >= 120 {
            i32::from(delta / 120)
        } else {
            i32::from(delta.signum())
        };
    }
    let (x, y) = (mouse.lLastX, mouse.lLastY);
    let (dx, dy) = if mouse.usFlags & MOUSE_MOVE_ABSOLUTE == 0 {
        state.absolute = None;
        (x as f32, y as f32)
    } else {
        // Tablets and remote desktops may report normalized absolute coordinates.
        let device = packet.header.hDevice as usize;
        let last = state.absolute.replace((device, x, y));
        let Some((previous, px, py)) = last else {
            return true;
        };
        if previous != device {
            return true;
        }
        let (w, h) = if mouse.usFlags & MOUSE_VIRTUAL_DESKTOP != 0 {
            (wm::SM_CXVIRTUALSCREEN, wm::SM_CYVIRTUALSCREEN)
        } else {
            (wm::SM_CXSCREEN, wm::SM_CYSCREEN)
        };
        // SAFETY: read-only desktop metrics.
        unsafe {
            (
                (x - px) as f32 * wm::GetSystemMetrics(w) as f32 / 65535.0,
                (y - py) as f32 * wm::GetSystemMetrics(h) as f32 / 65535.0,
            )
        }
    };
    state.motion.add(dx, dy, Instant::now());
    state.raw[0] += dx;
    state.raw[1] += dy;
    true
}

/// Whether a key press lets the mouse go: `Esc` with PC controls; in native
/// mode `Esc` pauses the title and keeps the mouse, while `Left Alt` or a
/// Windows key lets it go. Repeats do not count.
fn lets_go(msg: u32, wp: WPARAM, lp: LPARAM, native: bool) -> bool {
    if lp & (1 << 30) != 0 {
        return false;
    }
    let extended = lp & (1 << 24) != 0;
    match (msg, wp) {
        (wm::WM_KEYDOWN, 0x1B) => !native,
        (wm::WM_SYSKEYDOWN, 0x12) => native && !extended,
        (wm::WM_KEYDOWN | wm::WM_SYSKEYDOWN, 0x5B | 0x5C) => native,
        _ => false,
    }
}

pub(in crate::modules) fn window_message(
    hwnd: HWND,
    msg: u32,
    wp: WPARAM,
    lp: LPARAM,
) -> Option<LRESULT> {
    if !enabled() {
        return None;
    }
    match msg {
        wm::WM_INPUT if raw_motion(hwnd, lp) => {
            // SAFETY: raw input handled above; Windows requires foreground input cleanup.
            return Some(unsafe { wm::DefWindowProcW(hwnd, msg, wp, lp) });
        }
        wm::WM_SETFOCUS => acquire(hwnd),
        wm::WM_ACTIVATE if (wp as u16) != wm::WA_INACTIVE as u16 => acquire(hwnd),
        wm::WM_ACTIVATEAPP if wp == 0 => release(hwnd),
        wm::WM_KILLFOCUS | wm::WM_ENTERSIZEMOVE => release(hwnd),
        wm::WM_LBUTTONDOWN | wm::WM_RBUTTONDOWN => {
            if !WANTED.load(Relaxed) {
                WANTED.store(true, Relaxed);
                acquire(hwnd);
            }
        }
        wm::WM_NCDESTROY => {
            release(hwnd);
            // SAFETY: remove the properties while the title window still exists.
            unsafe {
                wm::RemovePropW(hwnd, w!("victory.pc_controls"));
                wm::RemovePropW(hwnd, w!("victory.driving_keys"));
            }
        }
        wm::WM_EXITSIZEMOVE => acquire(hwnd),
        wm::WM_SIZE if wp == wm::SIZE_MINIMIZED as usize => release(hwnd),
        wm::WM_MOVE | wm::WM_SIZE => {
            let mut state = lock(&CAPTURE);
            if state.window == hwnd as usize {
                state.clip = clip_to_client(hwnd).or(state.clip);
            }
        }
        wm::WM_KEYDOWN | wm::WM_SYSKEYDOWN if lets_go(msg, wp, lp, native::enabled()) => {
            // The title still gets the key (Esc pauses it via GameInput).
            if WANTED.swap(false, Relaxed) {
                release(hwnd);
                tracing::info!(captured = false, key = wp, "mouse look capture released");
            }
        }
        // F and F5 switch the PC layout; native keys have none.
        wm::WM_KEYDOWN
            if wp == usize::from(b'F')
                && lp & (1 << 30) == 0
                && auto_drive()
                && pc_controls() =>
        {
            // F enters / leaves a vehicle: W/S follow (throttle and brake in
            // a car, the stick on foot). The game still gets F; F5 resyncs
            // if F was pressed with no vehicle near.
            let driving = !DRIVING.fetch_xor(true, Relaxed);
            tracing::info!(driving, "PC controls layout switched by F (enter/exit vehicle)");
            // SAFETY: the panel displays the selected layer on this window.
            unsafe {
                if driving {
                    wm::SetPropW(hwnd, w!("victory.driving_keys"), 1usize as _);
                } else {
                    wm::RemovePropW(hwnd, w!("victory.driving_keys"));
                }
            }
        }
        wm::WM_KEYDOWN if wp == usize::from(VK_F5) && pc_controls() => {
            if lp & (1 << 30) == 0 {
                let was_driving = DRIVING.fetch_xor(true, Relaxed);
                let driving = !was_driving;
                tracing::info!(driving, "PC controls layout switched");
                // SAFETY: the panel displays the selected layer on this window.
                unsafe {
                    if was_driving {
                        wm::RemovePropW(hwnd, w!("victory.driving_keys"));
                    } else {
                        wm::SetPropW(hwnd, w!("victory.driving_keys"), 1usize as _);
                    }
                }
            }
            return Some(0);
        }
        wm::WM_KEYDOWN if wp == usize::from(VK_F6) => {
            if lp & (1 << 30) == 0 {
                let captured = !WANTED.fetch_xor(true, Relaxed);
                if captured {
                    acquire(hwnd);
                } else {
                    release(hwnd);
                }
                tracing::info!(captured, "mouse look capture toggled");
            }
            return Some(0);
        }
        wm::WM_SETCURSOR
            if (lp as u16) == wm::HTCLIENT as u16 && lock(&CAPTURE).window == hwnd as usize =>
        {
            // SAFETY: setting the cursor for our focused client area.
            unsafe {
                wm::SetCursor(null_mut());
            }
            return Some(1);
        }
        _ => (),
    }
    None
}

fn mouse_pad(pressed: u8, right_x: f32, right_y: f32, driving: bool) -> PadState {
    let mut pad = PadState {
        right_x,
        right_y,
        ..PadState::default()
    };
    if pressed & 4 != 0 {
        pad.buttons |= RIGHT_STICK;
    }
    if driving {
        if pressed & 1 != 0 {
            pad.buttons |= LEFT_SHOULDER;
        } // LMB: drive-by fire/aim (LB)
        if pressed & 2 != 0 {
            pad.buttons |= RIGHT_SHOULDER;
        } // RMB: vehicle action/handbrake (RB)
    } else {
        pad.left_trigger = f32::from((pressed >> 1) & 1);
        pad.right_trigger = f32::from(pressed & 1);
    }
    pad
}

pub(super) fn read(keys: &[KeyState]) -> PadState {
    let driving = DRIVING.load(Relaxed);
    let keyboard = pc_keyboard(keys, driving);
    let mut state = lock(&CAPTURE);
    let window = state.window as HWND;
    // SAFETY: only the focused title receives physical mouse inputs.
    if window.is_null() || unsafe { wm::GetForegroundWindow() } != window {
        return keyboard;
    }
    let held = mouse_buttons();
    state.blocked &= held;
    let pressed = held & !state.blocked;
    let [right_x, right_y] = state.motion.stick(Instant::now(), sensitivity(), invert_y());
    let pad = merged(keyboard, mouse_pad(pressed, right_x, right_y, driving));
    // The click-through control legend reads the virtual pad state, including
    // contextual A/B/X/Y prompts, without polling the desktop's physical keys.
    let flags = pad.buttons as usize
        | (usize::from(pad.left_trigger > 0.0) << 16)
        | (usize::from(pad.right_trigger > 0.0) << 17)
        | (usize::from(pad.left_x != 0.0 || pad.left_y != 0.0) << 18)
        | (usize::from(pad.right_x != 0.0 || pad.right_y != 0.0) << 19);
    if flags != state.last_flags {
        // SAFETY: a small integer value stored on the current title window.
        unsafe {
            wm::SetPropW(window, w!("victory.pc_buttons"), (flags + 1) as _);
        }
        state.last_flags = flags;
    }
    pad
}

/// Native input: what the mouse did since the last call, all zero while
/// the title's window does not have it. The context flags are left unset.
pub(super) fn read_native() -> NativeMouse {
    let mut state = lock(&CAPTURE);
    let window = state.window as HWND;
    // SAFETY: only the focused title receives physical mouse inputs.
    if window.is_null() || unsafe { wm::GetForegroundWindow() } != window {
        return NativeMouse::default();
    }
    let held = mouse_buttons();
    state.blocked &= held;
    let pressed = held & !state.blocked;
    // Whole counts; the rest waits for the next call.
    let whole = state.raw.map(f32::trunc);
    state.raw = [state.raw[0] - whole[0], state.raw[1] - whole[1]];
    let raw = (whole[0] as i32, whole[1] as i32);
    let wheel = std::mem::take(&mut state.wheel);
    let (frame, dt) = native::pad_frame();
    let look = (raw.0, if invert_y() { -raw.1 } else { raw.1 });
    let stick = state.look.step(super::now(), frame, dt, look, sensitivity());
    NativeMouse {
        buttons: [0x01, 0x02, 0x04, 0x05, 0x06]
            .into_iter()
            .enumerate()
            .filter(|&(i, _)| pressed & (1 << i) != 0)
            .map(|(_, vk)| vk)
            .collect(),
        stick,
        raw,
        wheel,
        ..NativeMouse::default()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn esc_lets_go_with_pc_controls_and_alt_or_win_in_native_mode() {
        let (down, sys, again, right) = (wm::WM_KEYDOWN, wm::WM_SYSKEYDOWN, 1 << 30, 1 << 24);
        assert!(lets_go(down, 0x1B, 0, false));
        assert!(!lets_go(down, 0x1B, 0, true));
        assert!(!lets_go(down, 0x1B, again, false));
        assert!(lets_go(sys, 0x12, 0, true));
        assert!(!lets_go(sys, 0x12, right, true));
        assert!(!lets_go(sys, 0x12, 0, false));
        assert!(lets_go(down, 0x5B, 0, true) && lets_go(sys, 0x5C, 0, true));
        assert!(!lets_go(down, 0x41, 0, true));
    }

    #[test]
    fn both_mouse_buttons_work_together_in_both_layouts() {
        let foot = mouse_pad(3, 0.4, -0.2, false);
        assert_eq!(
            (
                foot.left_trigger,
                foot.right_trigger,
                foot.right_x,
                foot.right_y
            ),
            (1.0, 1.0, 0.4, -0.2)
        );
        let car = mouse_pad(7, 0.0, 0.0, true);
        assert_eq!(
            (car.buttons, car.left_trigger, car.right_trigger),
            (LEFT_SHOULDER | RIGHT_SHOULDER | RIGHT_STICK, 0.0, 0.0)
        );
    }

    #[test]
    fn raw_motion_turns_right_and_up_then_stops_and_supports_invert_y() {
        let t = Instant::now();
        let mut m = Motion::default();
        m.add(2.0, -3.0, t);
        let [x, y] = m.stick(t, 1.0, false);
        assert!(x > 0.0 && y > x && x.hypot(y) <= 1.00001);
        assert_eq!(m.stick(t + Duration::from_millis(65), 1.0, false), [0.0; 2]);

        let mut inv = Motion::default();
        inv.add(0.0, -4.0, t);
        let [_, y_inv] = inv.stick(t, 2.0, true);
        assert!(y_inv < 0.0, "invert_y should flip dy polarity, got {y_inv}");

        m.add(-900.0, 900.0, t + Duration::from_millis(73));
        let [x, y] = m.stick(t + Duration::from_millis(73), 1.0, false);
        assert!(x < 0.0 && y < 0.0 && (x.hypot(y) - 1.0).abs() < 0.00001);
    }
}
