//! Native keyboard and mouse (`VICTORY_NATIVE_INPUT=1`), ported from
//! Vertex-NativeKBM-DevKit.
//!
//! In native mode the keys are the title's own keyboard input: the loader's
//! `keyboard_events` relays them to the title's actions (`native-keys.txt`),
//! so the stand-in pad no longer maps the keyboard. The pad keeps only what
//! the mouse does, routed by what the title shows (the loader reads the
//! context from the title's own actions):
//! - play: frame-locked camera look on the right stick ([`FrameLook`]);
//! - a radial wheel (weapon / radio): a held stick angle ([`WheelStick`]);
//! - a menu: mouse motion steps the D-pad ([`MenuStepper`]);
//! - the map: the mouse pans the cursor (left stick) and the wheel zooms
//!   (right / left trigger).
//!
//! The mouse buttons and the wheel reach the keyboard device as virtual keys
//! 0x7C to 0x80 (left, right, middle, 4, 5) and 0x81 / 0x82 (wheel up /
//! down), the names `native-keys.txt` binds.

use std::sync::LazyLock;
use std::sync::atomic::{AtomicU64, Ordering::Relaxed};
use std::time::{Duration, Instant};

use super::{DOWN, KeyState, LEFT, PadState, RIGHT, UP};

/// `VICTORY_NATIVE_INPUT=1`.
pub(super) fn enabled() -> bool {
    static ON: LazyLock<bool> =
        LazyLock::new(|| std::env::var_os("VICTORY_NATIVE_INPUT").is_some_and(|v| v == "1"));
    *ON
}

/// Wheel up / down as virtual keys for the keyboard device.
pub(super) const WHEEL_UP: u8 = 0x81;
pub(super) const WHEEL_DOWN: u8 = 0x82;

/// Mouse buttons (Windows virtual keys) and the key and scan code the
/// keyboard device reports for each (F13 to F17).
const BUTTON_KEYS: [(u8, u8, u32); 5] = [
    (0x01, 0x7C, 0x64), // left
    (0x02, 0x7D, 0x65), // right
    (0x04, 0x7E, 0x66), // middle
    (0x05, 0x7F, 0x67), // 4 (X1)
    (0x06, 0x80, 0x68), // 5 (X2)
];

/// What the mouse did since the previous poll, and what the title shows.
/// All zero while the title's window does not have the mouse.
#[derive(Clone, Debug, Default, PartialEq)]
pub(super) struct NativeMouse {
    /// Buttons held, as Windows virtual keys (0x01, 0x02, 0x04, 0x05, 0x06).
    pub buttons: Vec<u8>,
    /// Camera look ([`FrameLook`]), up positive.
    pub stick: (f32, f32),
    /// Raw motion since the previous poll, down positive.
    pub raw: (i32, i32),
    /// Wheel notches since the previous poll, up positive.
    pub wheel: i32,
    /// The title is in a menu (`keyboard_events::IN_MENU`).
    pub in_menu: bool,
    /// ... on the map (`keyboard_events::IN_MAP`).
    pub in_map: bool,
    /// A radial wheel is open (`keyboard_events::IN_WHEEL`).
    pub in_wheel: bool,
}

// ---- The title's frames -------------------------------------------------

/// Two reads of the stand-in pad closer than this are one frame.
const SAME_FRAME_US: u64 = 8_000;
/// Frame deltas used to normalize per-frame motion are kept in this range.
const MIN_DT_US: u64 = 10_000;
const MAX_DT_US: u64 = 80_000;

/// Frames the title has read the stand-in pad, the last read, and the gap
/// between the last two.
static PAD_FRAME: AtomicU64 = AtomicU64::new(0);
static PAD_LAST_US: AtomicU64 = AtomicU64::new(0);
static PAD_DT_US: AtomicU64 = AtomicU64::new(33_333);

/// The title read the stand-in pad (`GetCurrentReading`), at `now_us`.
pub(super) fn note_pad_frame(now_us: u64) {
    let prev = PAD_LAST_US.load(Relaxed);
    if prev == 0 {
        PAD_LAST_US.store(now_us, Relaxed);
        PAD_FRAME.fetch_add(1, Relaxed);
        return;
    }
    let gap = now_us.saturating_sub(prev);
    if gap < SAME_FRAME_US {
        return;
    }
    PAD_LAST_US.store(now_us, Relaxed);
    PAD_DT_US.store(gap.clamp(MIN_DT_US, MAX_DT_US), Relaxed);
    PAD_FRAME.fetch_add(1, Relaxed);
}

/// The title's frame count and the latest frame time, for [`FrameLook::step`].
pub(super) fn pad_frame() -> (u64, u64) {
    (PAD_FRAME.load(Relaxed), PAD_DT_US.load(Relaxed))
}

// ---- Camera look --------------------------------------------------------

/// Counts per second that push the stick all the way, at sensitivity 1.
const CAM_FULL_SPEED: f32 = 1400.0;
/// Where the slowest motion starts (titles ignore a stick near its centre).
const CAM_DEAD_ZONE: f32 = 0.13;
const CAM_CURVE_EXP: f32 = 0.62;
/// Motion this old no longer turns the camera, even within one frame.
const IDLE_RESET_US: u64 = 150_000;

/// Frame-locked mouse look: motion adds up until the title reads the pad,
/// then starts again from zero, so a frame's motion never bleeds into the
/// next one.
#[derive(Default)]
pub(super) struct FrameLook {
    last_frame: u64,
    last_motion: u64,
    dx: i32,
    dy: i32,
}

impl FrameLook {
    /// Adds `moved` (down positive) to the frame `frame` and returns the
    /// right stick (up positive).
    pub fn step(
        &mut self,
        now_us: u64,
        frame: u64,
        dt_us: u64,
        moved: (i32, i32),
        sensitivity: f32,
    ) -> (f32, f32) {
        if frame != self.last_frame {
            self.last_frame = frame;
            (self.dx, self.dy) = (0, 0);
        } else if (self.dx, self.dy) != (0, 0)
            && now_us.saturating_sub(self.last_motion) > IDLE_RESET_US
        {
            (self.dx, self.dy) = (0, 0);
        }
        if moved != (0, 0) {
            self.dx = self.dx.saturating_add(moved.0);
            self.dy = self.dy.saturating_add(moved.1);
            self.last_motion = now_us;
        }
        let x = self.dx as f32;
        let y = -(self.dy as f32);
        let length = x.hypot(y);
        if length == 0.0 {
            return (0.0, 0.0);
        }
        let dt_s = (dt_us.clamp(MIN_DT_US, MAX_DT_US) as f32) * 1e-6;
        let speed = length / (dt_s * CAM_FULL_SPEED) * sensitivity;
        let push = CAM_DEAD_ZONE + (1.0 - CAM_DEAD_ZONE) * speed.min(1.0).powf(CAM_CURVE_EXP);
        (x / length * push, y / length * push)
    }
}

// ---- Menus and wheels ---------------------------------------------------

/// Mouse motion in pause / settings menus (the Xbox build draws no pointer)
/// as D-pad steps.
#[derive(Default)]
pub(super) struct MenuStepper {
    acc_x: i32,
    acc_y: i32,
    last_motion: u64,
}

impl MenuStepper {
    const STEP_X: i32 = 56;
    const STEP_Y: i32 = 42;
    const IDLE_US: u64 = 250_000;

    pub fn clear(&mut self) {
        *self = MenuStepper::default();
    }

    /// Adds motion (down positive); the D-pad bit of a step crossed, or 0.
    pub fn step(&mut self, now_us: u64, (dx, dy): (i32, i32)) -> u32 {
        if now_us.saturating_sub(self.last_motion) > Self::IDLE_US {
            (self.acc_x, self.acc_y) = (0, 0);
        }
        if (dx, dy) != (0, 0) {
            self.acc_x = self.acc_x.saturating_add(dx);
            self.acc_y = self.acc_y.saturating_add(dy);
            self.last_motion = now_us;
        }
        if self.acc_y <= -Self::STEP_Y {
            self.acc_y += Self::STEP_Y;
            self.acc_x = 0;
            UP
        } else if self.acc_y >= Self::STEP_Y {
            self.acc_y -= Self::STEP_Y;
            self.acc_x = 0;
            DOWN
        } else if self.acc_x <= -Self::STEP_X {
            self.acc_x += Self::STEP_X;
            self.acc_y = 0;
            LEFT
        } else if self.acc_x >= Self::STEP_X {
            self.acc_x -= Self::STEP_X;
            self.acc_y = 0;
            RIGHT
        } else {
            0
        }
    }
}

/// A radial stick for the weapon / radio wheel: motion moves a point inside
/// the unit circle, held until the wheel closes (camera look lets go when
/// the mouse stops; a wheel selection must not).
#[derive(Default)]
pub(super) struct WheelStick {
    x: f32,
    y: f32,
}

impl WheelStick {
    const RADIUS: f32 = 95.0;
    const DEAD_ZONE: f32 = 0.14;

    pub fn clear(&mut self) {
        *self = WheelStick::default();
    }

    /// Adds motion (down positive); the held stick (up positive).
    pub fn step(&mut self, (dx, dy): (i32, i32), sensitivity: f32) -> (f32, f32) {
        let scale = sensitivity.max(0.2) / Self::RADIUS;
        self.x += dx as f32 * scale;
        self.y -= dy as f32 * scale;
        let length = self.x.hypot(self.y);
        if length > 1.0 {
            self.x /= length;
            self.y /= length;
        }
        if length < Self::DEAD_ZONE {
            (0.0, 0.0)
        } else {
            (self.x, self.y)
        }
    }
}

// ---- Short presses ------------------------------------------------------

/// A press is reported until the title has taken this many current readings
/// since it began: one would let the poll between a pad reading and a
/// keyboard reading of the same frame drop it.
const LATCH_LOOKS: u64 = 2;
/// ... or this long, for a title that is not reading at all.
const LATCH_MAX: Duration = Duration::from_secs(2);

/// Presses kept until the title has looked: a wheel notch is down for no
/// time at all, and would fall between two frames.
#[derive(Default)]
pub(super) struct Latch {
    /// (key or button, looks when the press began, when it began)
    held: Vec<(u32, u64, Instant)>,
}

impl Latch {
    /// What to report as down: `down` now, plus presses the title has not
    /// seen yet. `looks` is the title's current-reading count now.
    pub fn report(&mut self, down: &[u32], looks: u64, now: Instant) -> Vec<u32> {
        self.held.retain(|&(id, at, since)| {
            down.contains(&id)
                || (looks < at + LATCH_LOOKS && now.duration_since(since) < LATCH_MAX)
        });
        for &id in down {
            if !self.held.iter().any(|h| h.0 == id) {
                self.held.push((id, looks, now));
            }
        }
        self.held.iter().map(|h| h.0).collect()
    }
}

// ---- Routing ------------------------------------------------------------

/// What the mouse does to the stand-in pad and the keyboard device.
#[derive(Default)]
pub(super) struct Router {
    menu_stepper: MenuStepper,
    wheel_stick: WheelStick,
    /// Wheel notches as keys ([`WHEEL_UP`], [`WHEEL_DOWN`]).
    wheel_keys: Latch,
    /// Map zoom pulses from the wheel: 1 zooms in (right trigger), 2 out (left).
    map_zoom: Latch,
}

impl Router {
    /// The stand-in pad's share and the keys for the keyboard device.
    /// `looks`: the title's current readings so far.
    pub fn route(
        &mut self,
        mouse: &NativeMouse,
        sensitivity: f32,
        now_us: u64,
        looks: u64,
        now: Instant,
    ) -> (PadState, Vec<KeyState>) {
        let notch = |up, down| match mouse.wheel.cmp(&0) {
            std::cmp::Ordering::Greater => vec![up],
            std::cmp::Ordering::Less => vec![down],
            std::cmp::Ordering::Equal => Vec::new(),
        };
        let on_map = mouse.in_menu && mouse.in_map;

        let mut keys: Vec<KeyState> = BUTTON_KEYS
            .iter()
            .filter(|(button, ..)| mouse.buttons.contains(button))
            .map(|&(_, vk, scan)| native_key(vk, scan))
            .collect();
        let wheel_now = if on_map {
            Vec::new()
        } else {
            notch(u32::from(WHEEL_UP), u32::from(WHEEL_DOWN))
        };
        for vk in self.wheel_keys.report(&wheel_now, looks, now) {
            let scan = if vk == u32::from(WHEEL_UP) { 0x69 } else { 0x6A };
            keys.push(native_key(vk as u8, scan));
        }
        let zoom_now = if on_map { notch(1, 2) } else { Vec::new() };
        let zoom = self.map_zoom.report(&zoom_now, looks, now);

        let mut pad = PadState::default();
        if mouse.in_menu {
            self.wheel_stick.clear();
            if mouse.in_map {
                self.menu_stepper.clear();
                (pad.left_x, pad.left_y) = mouse.stick;
                pad.right_trigger = f32::from(u8::from(zoom.contains(&1)));
                pad.left_trigger = f32::from(u8::from(zoom.contains(&2)));
            } else {
                pad.buttons = self.menu_stepper.step(now_us, mouse.raw);
            }
        } else {
            self.menu_stepper.clear();
            if mouse.in_wheel {
                (pad.right_x, pad.right_y) = self.wheel_stick.step(mouse.raw, sensitivity);
            } else {
                self.wheel_stick.clear();
                (pad.right_x, pad.right_y) = mouse.stick;
            }
        }
        (pad, keys)
    }
}

fn native_key(virtual_key: u8, scan_code: u32) -> KeyState {
    KeyState {
        scan_code,
        virtual_key,
        ..Default::default()
    }
}

/// `keys` plus those of `extra` not held already.
pub(super) fn with_keys(mut keys: Vec<KeyState>, extra: Vec<KeyState>) -> Vec<KeyState> {
    for key in extra {
        if !keys.iter().any(|k| k.virtual_key == key.virtual_key) {
            keys.push(key);
        }
    }
    keys
}

#[cfg(test)]
mod tests {
    use super::*;

    const POLL: Duration = super::super::POLL;

    #[test]
    fn frame_look_stops_instantly_on_new_frame_without_bleed() {
        let mut look = FrameLook::default();
        let (x, y) = look.step(10_000, 1, 33_333, (20, -10), 1.0);
        assert!(x > CAM_DEAD_ZONE && y > 0.0);
        // Same frame: another poll with no new motion keeps the frame's motion.
        assert_eq!(look.step(18_000, 1, 33_333, (0, 0), 1.0), (x, y));
        // The title read frame 1: frame 2 starts with nothing left over.
        assert_eq!(look.step(26_000, 2, 33_333, (0, 0), 1.0), (0.0, 0.0));
    }

    #[test]
    fn menu_stepper_emits_crisp_dpad_steps() {
        let mut stepper = MenuStepper::default();
        assert_eq!(stepper.step(10_000, (0, 20)), 0);
        assert_eq!(stepper.step(20_000, (0, 25)), DOWN);
        assert_eq!(stepper.step(30_000, (0, 0)), 0);
        assert_eq!(stepper.step(40_000, (0, -50)), UP);
    }

    #[test]
    fn wheel_stick_holds_position_and_clamps_to_unit_circle() {
        let mut wheel = WheelStick::default();
        // A little jitter stays inside the dead zone.
        assert_eq!(wheel.step((5, 0), 1.0), (0.0, 0.0));
        // A flick up and right picks a wedge, held when the mouse stops.
        let (x, y) = wheel.step((120, -120), 1.0);
        assert!(x > 0.65 && y > 0.65);
        assert!((x.hypot(y) - 1.0).abs() < 1e-4);
        assert_eq!(wheel.step((0, 0), 1.0), (x, y));
        // Closing the wheel recentres it.
        wheel.clear();
        assert_eq!(wheel.step((0, 0), 1.0), (0.0, 0.0));
    }

    /// A tap that ends before the title looks is still reported, until the
    /// title has looked [`LATCH_LOOKS`] times.
    #[test]
    fn a_tap_between_two_looks_is_kept_until_the_title_has_looked() {
        let mut latch = Latch::default();
        let t = Instant::now();
        assert_eq!(latch.report(&[27], 10, t), [27]);
        assert_eq!(latch.report(&[], 10, t + POLL), [27]);
        assert_eq!(latch.report(&[], 11, t + POLL * 2), [27]);
        assert!(latch.report(&[], 12, t + POLL * 3).is_empty());
    }

    #[test]
    fn a_tap_is_dropped_after_a_while_without_looks() {
        let mut latch = Latch::default();
        let t = Instant::now();
        assert_eq!(latch.report(&[13], 3, t), [13]);
        assert_eq!(latch.report(&[], 3, t + LATCH_MAX / 2), [13]);
        assert!(latch.report(&[], 3, t + LATCH_MAX + POLL).is_empty());
    }

    #[test]
    fn play_routes_look_to_the_right_stick_and_buttons_to_keys() {
        let mut router = Router::default();
        let mouse = NativeMouse {
            buttons: vec![0x01, 0x05],
            stick: (0.5, -0.25),
            wheel: 1,
            ..Default::default()
        };
        let (pad, keys) = router.route(&mouse, 1.0, 0, 0, Instant::now());
        assert_eq!((pad.right_x, pad.right_y, pad.buttons), (0.5, -0.25, 0));
        let vks: Vec<u8> = keys.iter().map(|k| k.virtual_key).collect();
        assert_eq!(vks, [0x7C, 0x7F, WHEEL_UP]);
        assert_eq!(keys[0].scan_code, 0x64);
    }

    #[test]
    fn a_wheel_notch_stays_down_until_the_title_has_looked() {
        let mut router = Router::default();
        let t = Instant::now();
        let notch = NativeMouse {
            wheel: -1,
            ..Default::default()
        };
        let vks = |keys: Vec<KeyState>| keys.iter().map(|k| k.virtual_key).collect::<Vec<_>>();
        assert_eq!(vks(router.route(&notch, 1.0, 0, 5, t).1), [WHEEL_DOWN]);
        let still = NativeMouse::default();
        assert_eq!(vks(router.route(&still, 1.0, 0, 6, t + POLL).1), [WHEEL_DOWN]);
        assert!(router.route(&still, 1.0, 0, 7, t + POLL * 2).1.is_empty());
    }

    #[test]
    fn menus_step_the_dpad_and_the_map_pans_and_zooms() {
        let mut router = Router::default();
        let t = Instant::now();
        let menu = NativeMouse {
            raw: (0, 60),
            stick: (0.3, -0.9),
            in_menu: true,
            ..Default::default()
        };
        let (pad, _) = router.route(&menu, 1.0, 10_000, 0, t);
        assert_eq!(pad, PadState { buttons: DOWN, ..Default::default() });

        let map = NativeMouse {
            stick: (0.3, -0.9),
            wheel: 2,
            in_menu: true,
            in_map: true,
            ..Default::default()
        };
        let (pad, keys) = router.route(&map, 1.0, 20_000, 0, t);
        assert_eq!(
            pad,
            PadState {
                left_x: 0.3,
                left_y: -0.9,
                right_trigger: 1.0,
                ..Default::default()
            }
        );
        // The wheel zooms on the map; it presses no wheel key there.
        assert!(keys.is_empty());
    }

    #[test]
    fn an_open_wheel_holds_its_angle() {
        let mut router = Router::default();
        let t = Instant::now();
        let flick = NativeMouse {
            raw: (0, -200),
            stick: (0.0, 1.0),
            in_wheel: true,
            ..Default::default()
        };
        let (pad, _) = router.route(&flick, 1.0, 0, 0, t);
        assert!((pad.right_y - 1.0).abs() < 1e-4 && pad.right_x.abs() < 1e-4);
        let rest = NativeMouse {
            in_wheel: true,
            ..Default::default()
        };
        assert_eq!(router.route(&rest, 1.0, 0, 0, t).0, pad);
        // Wheel closed: back to camera look (the mouse is still).
        assert_eq!(router.route(&NativeMouse::default(), 1.0, 0, 0, t).0, PadState::default());
    }

    #[test]
    fn extra_keys_are_added_once() {
        let a = native_key(0x41, 1);
        let f13 = native_key(0x7C, 0x64);
        assert_eq!(with_keys(vec![a, f13], vec![f13]), [a, f13]);
    }
}
