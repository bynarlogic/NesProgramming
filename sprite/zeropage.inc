; =============================================================================
; zeropage.inc — zero-page variable layout ($0000-$00FF)
;
; WHY ZERO PAGE?
; The 6502's zero page ($0000-$00FF) is the fastest, most compact RAM.
; Instructions targeting zero-page addresses are one byte shorter and one
; cycle faster than those targeting other RAM. Use it for any variable that
; gets read or written every frame.
;
; HOW THIS WORKS:
; We use equates (=) to assign each variable a fixed address. This is the
; "explicit" approach — you control exactly where each variable lives.
;
; The alternative (used in larger projects) is:
;   .segment "ZEROPAGE"
;   sam_x: .res 1    ; .res N reserves N bytes, linker assigns the address
; That approach requires a ZEROPAGE segment in the .cfg file, but lets
; the linker pack variables automatically as your project grows.
;
; GOLDEN RULE: Keep all zero-page assignments here, in one place.
; Never scatter them across files — you'll accidentally use the same
; address twice and spend hours debugging it.
;
; FULL ZERO-PAGE MAP — update this whenever you add a variable:
;
;   $00  sam_x        — Sam's X screen position
;   $01  sam_y        — Sam's Y screen position
;   $02  frame_timer  — animation frame countdown
;   $03  anim_frame   — walk cycle frame index (0 or 1)
;   $04  moving       — nonzero if any direction held this frame
;   $05  sound_timer  — frames since last note retrigger
;   $06  duty_cycle   — APU_PULSE1_CTRL byte (set by A/B, read by sound)
;   $07  note_index   — which note to play (set by directions, read by sound)
;   $08-$FF  (available)
; =============================================================================

; --- Player state ---
sam_x       = $00   ; Sam's X position (0-255, wraps)
sam_y       = $01   ; Sam's Y position (0-255, clamped at $C0 by grass floor)

; --- Animation state ---
frame_timer = $02   ; Counts frames up to ANIM_RATE, then flips anim_frame
anim_frame  = $03   ; Current walk cycle frame: 0 (left foot) or 1 (right foot)

; --- Per-frame communication between player and sound/animation ---
; These are set by update_player each frame and read by other subroutines.
; Think of them as the "output interface" of update_player.
moving      = $04   ; Nonzero if Sam moved this frame; zero if idle

; --- Sound engine state ---
sound_timer = $05   ; Counts up to SOUND_RATE; reset when note retriggers
duty_cycle  = $06   ; Waveform shape byte for APU_PULSE1_CTRL
                    ; Default: DUTY_50. A button: DUTY_75. B button: DUTY_12.
note_index  = $07   ; Index 0-7 into note_lo/note_hi tables
                    ; Set by direction buttons: Right=0 Left=2 Up=4 Down=5
