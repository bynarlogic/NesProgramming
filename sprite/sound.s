; =============================================================================
; sound.s — APU Pulse 1 sound engine
;
; WHY THE NES NEEDS A RETRIGGER LOOP:
; The APU's length counter auto-silences notes after a short duration
; (controlled by bits 7-3 of APU_PULSE1_HI). Writing $4003 resets the
; length counter and restarts the note from the beginning of its envelope.
; To keep a note "ringing" continuously, you have to keep rewriting $4003.
; SOUND_RATE controls how often we retrigger (every N frames).
; =============================================================================

.segment "CODE"

; ---------------------------------------------------------------------------
; update_sound
;
; If Sam is moving, advances sound_timer and retriggers the note every
; SOUND_RATE frames. If Sam is idle, silences the channel immediately.
;
; RUNTIME vs. COMPILE-TIME indices:
; The play_note macro (macros.inc) requires a compile-time constant index.
; Here we use note_index, which is a runtime value set by update_player.
; We can't use the macro — instead we do the same register writes manually,
; substituting LDX note_index for LDX #constant. This is a common pattern
; when table-driven data must be selected by game logic at runtime.
;
; Inputs:   moving, note_index, duty_cycle, sound_timer
; Outputs:  sound_timer (zero-page)
;           APU_PULSE1_CTRL ($4000), APU_PULSE1_LO ($4002), APU_PULSE1_HI ($4003)
; Clobbers: A, X
;
; Called by: nmi_handler (must run AFTER update_player sets moving/note_index)
; ---------------------------------------------------------------------------
.proc update_sound

    lda moving
    bne @is_moving
    jmp @silence            ; idle: not moving — BEQ range is too short, invert + JMP

@is_moving:
    inc sound_timer
    lda sound_timer
    cmp #SOUND_RATE
    beq @retrigger
    jmp @done               ; timer counting — note rings on, nothing to do

@retrigger:
    ; Reset timer and retrigger the note
    lda #$00
    sta sound_timer

    ; --- Write APU registers (runtime version of play_note macro) ---
    lda duty_cycle          ; waveform shape set by A/B buttons this frame
    sta APU_PULSE1_CTRL
    ldx note_index          ; runtime variable — which note did the player choose?
    lda note_lo,x
    sta APU_PULSE1_LO
    lda note_hi,x
    ora #$08                ; ensure length counter bits are nonzero (instant silence if $00)
    sta APU_PULSE1_HI       ; writing this register always retriggers the note
    jmp @done

@silence:
    lda #$00
    sta sound_timer         ; reset timer so the note retriggers immediately on next move
    sta APU_PULSE1_CTRL     ; volume = 0 → silence; does NOT retrigger length counter

@done:
    rts
.endproc
