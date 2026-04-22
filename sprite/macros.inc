; =============================================================================
; macros.inc — assembler macros
;
; MACROS vs. SUBROUTINES — the key organizational tradeoff:
;
;   MACRO       The assembler pastes a copy of the code at every call site.
;               No JSR/RTS overhead (saves ~12 cycles per call).
;               But every call site gets its own copy: more ROM space used.
;               Best for: small, speed-critical snippets used in 1-2 places.
;
;   SUBROUTINE  One copy of the code; caller uses JSR + RTS (~12 cycle round trip).
;               Saves ROM space — all callers share a single copy.
;               Best for: anything longer than ~4 instructions, or used in
;               more than one place.
;
; MACROS also have a key limitation: arguments must be compile-time constants.
; If you need to pass a runtime variable (e.g., "play whichever note the player
; chose"), you can't use a macro — you need a subroutine or inline code that
; reads the variable at runtime. See update_sound in sound.s for that pattern.
; =============================================================================

; play_note <index>
;
; Fires a note on APU Pulse 1.
;
; Arguments:
;   index — compile-time constant (0-7), selects a row in note_lo/note_hi
;
; Reads from zero-page:
;   duty_cycle ($06) — the waveform shape byte set by the A/B buttons
;
; Clobbers: A, X
;
; NOTE: Because `index` must be a compile-time constant, this macro can't
; respond to which note the player chose at runtime. For that, see the inline
; note-playing code in update_sound (sound.s), which uses LDX note_index
; instead of LDX #immediate.
.macro play_note index
    lda duty_cycle
    sta APU_PULSE1_CTRL
    ldx #index               ; compile-time constant — baked directly into the opcode
    lda note_lo,x
    sta APU_PULSE1_LO
    lda note_hi,x
    ora #$08                 ; bits 7-3 = length counter load — must be nonzero
    sta APU_PULSE1_HI        ; writing APU_PULSE1_HI always retriggers the note
.endmacro
