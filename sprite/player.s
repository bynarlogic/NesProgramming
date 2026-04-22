; =============================================================================
; player.s — Sam's movement, OAM positioning, and walk animation
;
; SUBROUTINES (called with JSR, return with RTS):
;   update_player    — reads controller, moves Sam, sets note_index/duty_cycle
;   update_oam       — writes sam_x/sam_y to shadow OAM position bytes
;   update_animation — manages walk cycle, writes tile indices to shadow OAM
;
; ENCAPSULATION IN ASSEMBLY:
; True encapsulation (private memory, type safety) doesn't exist in assembly.
; What we CAN do is discipline: each subroutine has a documented "contract":
;   - Inputs:  which zero-page variables it reads (caller must set these first)
;   - Outputs: which zero-page variables / memory it writes
;   - Clobbers: which CPU registers it trashes (A, X, Y)
;
; Callers must not depend on register values after a JSR. If you need to
; preserve a register across a call, push it before (PHA/PHX/PHY) and
; pull it after (PLA/PLX/PLY).
;
; The @ prefix makes a label LOCAL to its .proc — it can only be referenced
; within that same .proc. This is assembly's version of "private" scope.
; =============================================================================

.segment "CODE"

; ---------------------------------------------------------------------------
; update_player
;
; Reads controller 1 and updates Sam's position and sound parameters.
;
; Inputs:    controller hardware (no zero-page inputs)
; Outputs:   sam_x, sam_y, moving, note_index, duty_cycle
; Clobbers:  A, X
;
; Called by: nmi_handler (must run BEFORE update_sound, update_oam,
;            update_animation — all three read variables written here)
; ---------------------------------------------------------------------------
.proc update_player

    ; Default duty cycle for this frame. A/B buttons below can override it.
    ; Because this resets every frame, buttons must be HELD — not just tapped —
    ; to change the duty cycle. That's the "automated" behavior Josh added.
    lda #DUTY_50
    sta duty_cycle

    ; --- Strobe controller 1 to latch all 8 button states ---
    ; Writing $01 then $00 loads the controller's internal shift register.
    ; After the strobe, each read of CONTROLLER1 clocks out the next button
    ; in bit 0 (1=pressed, 0=not pressed).
    ; Read order is fixed by hardware: A, B, Select, Start, Up, Down, Left, Right
    lda #$01
    sta CONTROLLER1         ; strobe on
    lda #$00
    sta CONTROLLER1         ; strobe off — buttons are now latched and ready

    ; Clear per-frame flags (will be set below if a button is pressed)
    sta moving              ; assume idle until a direction is read
    sta note_index          ; default to note 0 (C2); overwritten by directions

    ; --- A button: 75% duty cycle (fatter square wave) ---
    lda CONTROLLER1
    and #$01
    beq @no_a
        lda #DUTY_75
        sta duty_cycle
@no_a:

    ; --- B button: 12.5% duty cycle (thin, buzzy) ---
    lda CONTROLLER1
    and #$01
    beq @no_b
        lda #DUTY_12
        sta duty_cycle
@no_b:

    lda CONTROLLER1         ; Select — discard
    lda CONTROLLER1         ; Start  — discard

    ; --- Directional buttons ---
    ; Each direction: move Sam one pixel, set moving=1, record note_index.
    ; If multiple directions are held, the last one read wins (Right beats Left).
    ; This is because each direction overwrites note_index unconditionally.

    ; Up → note index 4 (G2, ~98 Hz)
    lda CONTROLLER1
    and #$01
    beq @no_up
        dec sam_y
        lda #$01
        sta moving
        lda #$04
        sta note_index
@no_up:

    ; Down → note index 5 (A2, ~110 Hz)
    ; Includes a floor clamp: sam_y is capped at $BF so Sam can't walk into the grass.
    lda CONTROLLER1
    and #$01
    beq @no_down
        lda #$01
        sta moving
        lda #$05
        sta note_index
        inc sam_y
        lda sam_y
        cmp #$C0            ; carry set if sam_y >= $C0 (at or past the grass)
        bcc @no_down        ; carry clear = still above grass, keep position
        lda #$BF            ; snap back to just above the grass floor
        sta sam_y
@no_down:

    ; Left → note index 2 (E2, ~82 Hz)
    lda CONTROLLER1
    and #$01
    beq @no_left
        dec sam_x
        lda #$01
        sta moving
        lda #$02
        sta note_index
@no_left:

    ; Right → note index 0 (C2, ~65 Hz)
    lda CONTROLLER1
    and #$01
    beq @no_right
        inc sam_x
        lda #$01
        sta moving
        lda #$00
        sta note_index
@no_right:

    rts
.endproc


; ---------------------------------------------------------------------------
; update_oam
;
; Writes Sam's current position into the shadow OAM ($0200-$02FF).
; Sam is 2 tiles wide × 3 tiles tall, so we update 6 sprite slots.
;
; Shadow OAM slot layout:
;   $0200-$0203  row 0 left   (Y, tile, attr, X)
;   $0204-$0207  row 0 right
;   $0208-$020B  row 1 left
;   $020C-$020F  row 1 right
;   $0210-$0213  row 2 left
;   $0214-$0217  row 2 right
;
; We only update Y (byte 0) and X (byte 3) here.
; Tile indices (byte 1) are handled by update_animation.
; Attributes (byte 2) never change and were set by the sam_oam template.
;
; Inputs:   sam_x, sam_y
; Outputs:  $0200, $0204, $0208, $020C, $0210, $0214 (Y bytes)
;           $0203, $0207, $020B, $020F, $0213, $0217 (X bytes)
; Clobbers: A
; ---------------------------------------------------------------------------
.proc update_oam

    ; --- Y positions (OAM byte 0 of each sprite entry) ---
    lda sam_y
    sta $0200               ; row 0 (head): left  Y
    sta $0204               ; row 0 (head): right Y
    clc
    adc #$08
    sta $0208               ; row 1 (body): left  Y
    sta $020C               ; row 1 (body): right Y
    clc
    adc #$08
    sta $0210               ; row 2 (feet): left  Y
    sta $0214               ; row 2 (feet): right Y

    ; --- X positions (OAM byte 3 of each sprite entry) ---
    lda sam_x
    sta $0203               ; row 0 (head): left  X
    sta $020B               ; row 1 (body): left  X
    sta $0213               ; row 2 (feet): left  X
    clc
    adc #$08
    sta $0207               ; row 0 (head): right X
    sta $020F               ; row 1 (body): right X
    sta $0217               ; row 2 (feet): right X

    rts
.endproc


; ---------------------------------------------------------------------------
; update_animation
;
; Advances Sam's walk cycle while moving and writes tile indices to
; shadow OAM (byte 1 of each sprite entry).
;
; Walk cycle: frame_timer counts frames up to ANIM_RATE, then anim_frame
; flips between 0 and 1 (EOR #$01). When Sam stops, anim_frame resets to 0
; (the idle/default pose).
;
; Tile table access:
;   Each row has 4 entries: [frame0_left, frame0_right, frame1_left, frame1_right]
;   base  = anim_frame * 2    head offset = base, body offset = base+4, feet = base+8
;
; Inputs:   moving, frame_timer, anim_frame
; Outputs:  frame_timer, anim_frame (zero-page)
;           $0201, $0205 (head tile indices)
;           $0209, $020D (body tile indices)
;           $0211, $0215 (feet tile indices)
; Clobbers: A, X
; ---------------------------------------------------------------------------
.proc update_animation

    ; --- Advance or reset the animation counter ---
    lda moving
    bne @do_anim
        ; Sam is idle — snap to frame 0 and skip the timer
        lda #$00
        sta anim_frame
        jmp @write_tiles
@do_anim:
    inc frame_timer
    lda frame_timer
    cmp #ANIM_RATE
    bne @write_tiles        ; timer hasn't fired yet — just redraw current frame
        lda #$00
        sta frame_timer
        lda anim_frame
        eor #$01            ; flip between 0 and 1
        sta anim_frame

@write_tiles:
    ; --- Write tile indices to shadow OAM byte 1 for all 6 sprites ---

    ; Head row (anim_tiles offset 0)
    lda anim_frame
    asl                     ; × 2 → index 0 (frame 0) or 2 (frame 1)
    tax
    lda anim_tiles,x        ; left tile
    sta $0201
    inx
    lda anim_tiles,x        ; right tile
    sta $0205

    ; Body row (anim_tiles offset 4)
    lda anim_frame
    asl
    clc
    adc #$04
    tax
    lda anim_tiles,x
    sta $0209
    inx
    lda anim_tiles,x
    sta $020D

    ; Feet row (anim_tiles offset 8)
    lda anim_frame
    asl
    clc
    adc #$08
    tax
    lda anim_tiles,x
    sta $0211
    inx
    lda anim_tiles,x
    sta $0215

    rts
.endproc
