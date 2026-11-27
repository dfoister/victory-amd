# Vertex native controls: GTA V Enhanced style key binding for the game's own actions. Edits data\native-keys.txt;
# a running game takes the changes within a second (no restart). Pick an action, press Assign, press a key or mouse
# button. Reset puts back the GTA V Enhanced defaults (data\native-keys.default.txt).
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
$here = $PSScriptRoot
$file = Join-Path $here 'data\native-keys.txt'
$defaults = Join-Path $here 'data\native-keys.default.txt'
$namesFile = Join-Path $here 'data\controls-actions.txt'

# --- the layout: per key, play actions | menu actions (as the file has them) ---
function Read-Layout([string]$path) {
    $layout = [ordered]@{}
    foreach ($line in Get-Content $path -ErrorAction SilentlyContinue) {
        $l = ($line -split '#')[0]
        if ($l -notmatch '=') { continue }
        $key, $rest = $l -split '=', 2
        $play, $menu = $rest -split '\|', 2
        $layout[$key.Trim()] = @{
            play = @($play -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
            menu = @($menu -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        }
    }
    $layout
}
$script:layout = Read-Layout $file

# Order inside a key: vehicle, aircraft/bike, on foot, parachute, phone, script; menus after '|'.
function Get-Rank([string]$a) {
    switch -regex ($a) {
        '^INPUT_VEH_(FLY_|SUB_|PUSHBIKE_|PLANE_|HELI_)' { return 1.5 }
        '^INPUT_VEH_' { return 1 }
        '^INPUT_(PARACHUTE_|SKIP_CUTSCENE)' { return 2.5 }
        '^INPUT_CELLPHONE_' { return 3 }
        '^INPUT_(SCRIPT_|SCRIPTED_)' { return 4 }
        default { return 2 }
    }
}
function Test-Menu([string]$a) { ($a -match '^INPUT_(FRONTEND_|CURSOR_|GAME_MENU_|MAP_MENU_)') -and $a -ne 'INPUT_FRONTEND_PAUSE' }

function Get-Category([string]$a) {
    switch -regex ($a) {
        '^INPUT_VEH_(FLY_|PLANE_|HELI_)' { 'Aircraft'; break }
        '^INPUT_VEH_(SUB_|BOAT_)' { 'Boat / Sub'; break }
        '^INPUT_VEH_PUSHBIKE_' { 'Bicycle'; break }
        '^INPUT_VEH_' { 'Vehicle'; break }
        '^INPUT_PARACHUTE_' { 'Parachute'; break }
        '^INPUT_(CELLPHONE_|PHONE)' { 'Phone'; break }
        '^INPUT_(FRONTEND_|CURSOR_|GAME_MENU_|MAP_MENU_|SHOP_MENU_)' { 'Menus'; break }
        '^INPUT_(MELEE_)' { 'Melee'; break }
        '^INPUT_(SCRIPT_|SCRIPTED_|MINIGAME_|REPLAY_|CREATOR_)' { 'Other'; break }
        default { 'On Foot' }
    }
}
function Get-Pretty([string]$a) {
    $s = $a -replace '^INPUT_', '' -replace '^VEH_(FLY_|PLANE_|SUB_|PUSHBIKE_)?', '' -replace '^(CELLPHONE_|FRONTEND_|PARACHUTE_)', ''
    (Get-Culture).TextInfo.ToTitleCase(($s -replace '_', ' ').ToLower())
}

# Keys of an action, from the layout.
function Get-Keys([string]$a) {
    @($script:layout.Keys | Where-Object { $script:layout[$_].play -contains $a -or $script:layout[$_].menu -contains $a })
}
function Remove-Action([string]$a) {
    foreach ($k in @($script:layout.Keys)) {
        $e = $script:layout[$k]
        $e.play = @($e.play | Where-Object { $_ -ne $a }); $e.menu = @($e.menu | Where-Object { $_ -ne $a })
        if ($e.play.Count -eq 0 -and $e.menu.Count -eq 0) { $script:layout.Remove($k) }
    }
}
function Add-Binding([string]$key, [string]$a) {
    if (-not $script:layout.Contains($key)) { $script:layout[$key] = @{ play = @(); menu = @() } }
    $e = $script:layout[$key]
    if (Test-Menu $a) { if ($e.menu -notcontains $a) { $e.menu = @($e.menu + $a) } }
    else { if ($e.play -notcontains $a) { $e.play = @($e.play + $a | Sort-Object { Get-Rank $_ }) } }
}
function Save-Layout {
    $out = @('# Vertex native keys (edited with Controls.ps1). KEY = play actions | menu actions; the game does the first',
             '# action on the line it has active. Changes apply while playing.', '')
    foreach ($k in $script:layout.Keys) {
        $e = $script:layout[$k]
        $line = "$k = " + ($e.play -join ', ')
        if ($e.menu.Count) { $line += ' | ' + ($e.menu -join ', ') }
        $out += $line
    }
    Set-Content -Path $file -Value $out -Encoding utf8
}

# --- key names (native-keys.txt) from a key press or a mouse button ---
function Get-KeyName([System.Windows.Forms.KeyEventArgs]$e) {
    $k = $e.KeyCode
    $map = @{ Space = 'Space'; ShiftKey = 'Shift'; LShiftKey = 'Shift'; RShiftKey = 'RightShift'; ControlKey = 'Ctrl';
        LControlKey = 'Ctrl'; RControlKey = 'RightCtrl'; Menu = 'Alt'; Tab = 'Tab'; Escape = 'Esc'; Return = 'Enter';
        Back = 'Backspace'; Capital = 'CapsLock'; Insert = 'Insert'; Delete = 'Delete'; Home = 'Home'; End = 'End';
        PageUp = 'PageUp'; PageDown = 'PageDown'; Up = 'ArrowUp'; Down = 'ArrowDown'; Left = 'ArrowLeft';
        Right = 'ArrowRight'; Oemcomma = 'Comma'; OemPeriod = 'Period'; OemMinus = 'Minus'; Oemplus = 'Equals';
        OemOpenBrackets = 'LeftBracket'; Oem6 = 'RightBracket'; Oem1 = 'Semicolon'; Oem7 = 'Quote';
        OemQuestion = 'Slash'; Oem5 = 'Backslash'; Oemtilde = 'Backquote' }
    $n = "$k"
    if ($map.ContainsKey($n)) { return $map[$n] }
    if ($n -match '^[A-Z]$') { return $n }
    if ($n -match '^D([0-9])$') { return $Matches[1] }
    if ($n -match '^F([1-9]|1[0-2])$') { return $n }
    if ($n -match '^NumPad([0-9])$') { return "Numpad$($Matches[1])" }
    $null
}
function Get-MouseName([System.Windows.Forms.MouseButtons]$b) {
    switch ("$b") { 'Left' { 'LeftClick' } 'Right' { 'RightClick' } 'Middle' { 'MiddleClick' } 'XButton1' { 'Mouse4' } 'XButton2' { 'Mouse5' } default { $null } }
}

# --- window ---
$actions = @(Get-Content $namesFile | Where-Object { $_.Trim() } | ForEach-Object { ($_ -split '\s+')[1] } |
    Where-Object { $_ -notmatch '^INPUT_(REPLAY_|CREATOR_|MINIGAME_)' } | Sort-Object -Unique)
$form = New-Object Windows.Forms.Form
$form.Text = 'Vertex Controls (keyboard and mouse)'; $form.Size = New-Object Drawing.Size(820, 640)
$form.BackColor = [Drawing.Color]::FromArgb(24, 18, 36); $form.ForeColor = [Drawing.Color]::White
$form.Font = New-Object Drawing.Font('Segoe UI', 10)
$filter = New-Object Windows.Forms.ComboBox; $filter.DropDownStyle = 'DropDownList'; $filter.Location = '12,12'; $filter.Width = 180
@('All', 'On Foot', 'Vehicle', 'Aircraft', 'Boat / Sub', 'Bicycle', 'Parachute', 'Melee', 'Phone', 'Menus', 'Other') | ForEach-Object { [void]$filter.Items.Add($_) }
$filter.SelectedIndex = 0
$search = New-Object Windows.Forms.TextBox; $search.Location = '204,12'; $search.Width = 260
$hint = New-Object Windows.Forms.Label; $hint.Location = '476,15'; $hint.AutoSize = $true; $hint.Text = 'search'
$list = New-Object Windows.Forms.ListView; $list.View = 'Details'; $list.FullRowSelect = $true; $list.MultiSelect = $false
$list.Location = '12,48'; $list.Size = New-Object Drawing.Size(780, 480); $list.Anchor = 'Top,Bottom,Left,Right'
$list.BackColor = [Drawing.Color]::FromArgb(36, 28, 54); $list.ForeColor = [Drawing.Color]::White
[void]$list.Columns.Add('Action', 300); [void]$list.Columns.Add('Category', 120); [void]$list.Columns.Add('Keys', 330)
function Update-List {
    $list.BeginUpdate(); $list.Items.Clear()
    foreach ($a in $actions) {
        $cat = Get-Category $a
        if ($filter.SelectedItem -ne 'All' -and $cat -ne $filter.SelectedItem) { continue }
        $pretty = Get-Pretty $a
        if ($search.Text -and ($pretty + $a) -notmatch [regex]::Escape($search.Text)) { continue }
        $it = New-Object Windows.Forms.ListViewItem($pretty); [void]$it.SubItems.Add($cat)
        [void]$it.SubItems.Add(((Get-Keys $a) -join ', ')); $it.Tag = $a; [void]$list.Items.Add($it)
    }
    $list.EndUpdate()
}
$status = New-Object Windows.Forms.Label; $status.Location = '12,575'; $status.AutoSize = $true; $status.Anchor = 'Bottom,Left'
function New-Button([string]$text, [int]$x) { $b = New-Object Windows.Forms.Button; $b.Text = $text; $b.Location = "$x,538"; $b.Size = '150,30'; $b.Anchor = 'Bottom,Left'; $b.BackColor = [Drawing.Color]::FromArgb(110, 60, 190); $b.FlatStyle = 'Flat'; $b }
$assign = New-Button 'Assign key...' 12; $add = New-Button 'Add key...' 170; $clear = New-Button 'Clear' 328; $reset = New-Button 'Reset to defaults' 486
function Read-Binding {
    $dlg = New-Object Windows.Forms.Form; $dlg.Text = 'Press a key, mouse button, or scroll wheel (Esc+Shift cancels)'; $dlg.Size = '500,145'
    $dlg.StartPosition = 'CenterParent'; $dlg.KeyPreview = $true; $dlg.BackColor = $form.BackColor; $dlg.ForeColor = 'White'
    $lbl = New-Object Windows.Forms.Label; $lbl.Text = 'Press the key, mouse button, or scroll mouse wheel for this action...'; $lbl.AutoSize = $true; $lbl.Location = '20,35'
    $dlg.Controls.Add($lbl); $script:picked = $null
    $dlg.Add_KeyDown({ param($s, $e) if ($e.KeyCode -eq 'Escape' -and $e.Shift) { $dlg.Close(); return }; $n = Get-KeyName $e; if ($n) { $script:picked = $n; $dlg.Close() }; $e.SuppressKeyPress = $true })
    $handler = { param($s, $e) $n = Get-MouseName $e.Button; if ($n) { $script:picked = $n; $dlg.Close() } }
    $wheelHandler = { param($s, $e) if ($e.Delta -gt 0) { $script:picked = 'WheelUp'; $dlg.Close() } elseif ($e.Delta -lt 0) { $script:picked = 'WheelDown'; $dlg.Close() } }
    $dlg.Add_MouseDown($handler); $lbl.Add_MouseDown($handler)
    $dlg.Add_MouseWheel($wheelHandler); $lbl.Add_MouseWheel($wheelHandler)
    [void]$dlg.ShowDialog($form); $script:picked
}
function Set-Binding([bool]$replace) {
    if ($list.SelectedItems.Count -eq 0) { $status.Text = 'Pick an action first.'; return }
    $a = $list.SelectedItems[0].Tag; $k = Read-Binding
    if (-not $k) { return }
    if ($replace) { Remove-Action $a }
    Add-Binding $k $a; Save-Layout; Update-List
    $status.Text = "$(Get-Pretty $a) = $k (saved; a running game uses it within a second)"
}
$assign.Add_Click({ Set-Binding $true }); $add.Add_Click({ Set-Binding $false })
$clear.Add_Click({ if ($list.SelectedItems.Count) { $a = $list.SelectedItems[0].Tag; Remove-Action $a; Save-Layout; Update-List; $status.Text = "$(Get-Pretty $a): no key (saved)" } })
$reset.Add_Click({ Copy-Item $defaults $file -Force; $script:layout = Read-Layout $file; Update-List; $status.Text = 'GTA V Enhanced defaults put back (saved).' })
$list.Add_DoubleClick({ Set-Binding $true })
$filter.Add_SelectedIndexChanged({ Update-List }); $search.Add_TextChanged({ Update-List })
$form.Controls.AddRange(@($filter, $search, $hint, $list, $assign, $add, $clear, $reset, $status))
$status.Text = "$($actions.Count) actions. Double-click or Assign (supports WheelUp/Down). In game: Left Alt/Win frees mouse."
Update-List
if ($env:VERTEX_CONTROLS_TEST) { return }   # tests load the functions without the window
$form.Add_Shown({ $form.WindowState = 'Normal'; $form.TopMost = $true; $form.Activate(); $form.TopMost = $false })
[void]$form.ShowDialog()
