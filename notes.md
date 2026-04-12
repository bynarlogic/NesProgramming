# NES Programming Notes

## Number Formats in ca65

```asm
.byte 78        ; decimal
.byte $4E       ; hex      ← most common in NES code
.byte %01001110 ; binary   ← used when flipping specific hardware bits
```

## Hex Cheatsheet

Hex digits: `0 1 2 3 4 5 6 7 8 9 A B C D E F`
Each digit = 4 bits. Two hex digits = one byte ($00–$FF = 0–255).

**Quick trick:** Left digit is the "sixteens place."
So $4E = (4 × 16) + 14 = 64 + 14 = 78.

### Counting
```
$00 =   0       $08 =   8
$01 =   1       $09 =   9
$02 =   2       $0A =  10
$03 =   3       $0B =  11
$04 =   4       $0C =  12
$05 =   5       $0D =  13
$06 =   6       $0E =  14
$07 =   7       $0F =  15

$10 =  16       $80 = 128
$20 =  32       $FF = 255
$40 =  64
```

### ASCII Uppercase
```
A=$41  B=$42  C=$43  D=$44  E=$45  F=$46  G=$47  H=$48
I=$49  J=$4A  K=$4B  L=$4C  M=$4D  N=$4E  O=$4F  P=$50
Q=$51  R=$52  S=$53  T=$54  U=$55  V=$56  W=$57  X=$58
Y=$59  Z=$5A
```

## iNES Header

The first 16 bytes of every NES ROM. Tells the emulator what kind of cartridge this is.

```asm
.segment "HEADER"
    .byte $4E, $45, $53, $1A  ; "NES" + $1A (EOF marker) — magic signature
    .byte $02                  ; 2 PRG-ROM banks (2 × 16KB = 32KB)
    .byte $01                  ; 1 CHR-ROM bank (8KB)
    .byte $00                  ; Mapper 0, no mirroring flags
    .byte $00                  ; Mapper 0 (high nibble), standard iNES
    .byte $00, $00, $00, $00   ; Padding (bytes 8–11)
    .byte $00, $00, $00, $00   ; Padding (bytes 12–15)
```

- Byte 3 is $1A (not $10) — ASCII Ctrl+Z, a DOS EOF marker
- The NES CPU never sees the header — it's purely for emulators and tools
- Mapper 0 = NROM, the simplest cartridge type

## NES Program Structure

Every NES ROM needs three fundamental pieces:
1. **Header** — tells the emulator what kind of cartridge this is
2. **PRG-ROM** — your program code (the CPU runs this)
3. **CHR-ROM** — graphics data (the PPU reads this)

At the end of PRG-ROM: the **interrupt vectors** — three addresses telling the CPU
where to jump on power-on (RESET), NMI, and IRQ.

## NES Color Palette

The NES has 64 possible colors, each a single byte value:

```
$0F = black    $30 = white
$06 = dark red $16 = red
$21 = blue     $2A = green
$28 = yellow   $13 = purple
```

The universal background color lives at PPU address **$3F00**.
To write a color there, you set PPUADDR twice (high byte, then low byte),
then write the color value to PPUDATA.

```asm
bit PPUSTATUS       ; reset the address latch first — always do this
lda #$3F
sta PPUADDR         ; high byte of $3F00
lda #$00
sta PPUADDR         ; low byte of $3F00
lda #$21            ; Megaman blue
sta PPUDATA         ; write color to $3F00
```

## PPUMASK — Rendering Control ($2001)

Each bit is a switch. Write the right combination to turn on what you need.

```
Bit:  7     6     5     4     3     2     1     0
      B     G     R     s     b     M     m     .
                              ^           ^
                         show bg     show left edge
```

```asm
lda #%00001010   ; bits 3 and 1 — background on, left edge on
sta PPUMASK
```

`$00` = rendering off. `$0A` = background on.

## Reset Handler — Full Structure

Every NES program starts here. Goes from power-on chaos to a stable state.

```asm
.proc reset_handler
    sei              ; disable IRQs
    cld              ; disable decimal mode (not used on NES)
    ldx #$FF
    txs              ; set stack pointer to top of stack ($01FF)

@vblankwait1:        ; wait for PPU to warm up — first VBlank
    bit PPUSTATUS
    bpl @vblankwait1

@vblankwait2:        ; wait for second VBlank
    bit PPUSTATUS
    bpl @vblankwait2

    ; ... set palette, enable rendering ...

@loop:
    jmp @loop        ; loop forever
.endproc
```

## Interrupt Vectors

Three addresses at the very end of PRG-ROM. Tell the CPU where to jump.

```asm
.proc nmi_handler
    rti              ; return from interrupt (stub)
.endproc

.proc irq_handler
    rti
.endproc

.segment "VECTORS"
    .word nmi_handler    ; $FFFA — fires every VBlank
    .word reset_handler  ; $FFFC — fires on power-on / reset
    .word irq_handler    ; $FFFE — hardware interrupts
```

`.word` writes a 16-bit address (two bytes).
`rti` = Return from Interrupt — minimum valid handler.

## Assembling with ca65

Two steps: assemble, then link.

```bash
ca65 background.s -o background.o    # assemble → object file
ld65 -C background.cfg background.o -o background.nes  # link → ROM
```

The `.cfg` file tells ld65 how to lay out the ROM:
- HEADER (16 bytes) → PRG-ROM (32KB, $8000–$FFFF) → CHR-ROM (8KB)
- Vectors are pinned to $FFFA–$FFFF at the end of PRG

## NES Has No Built-in Character Set

- Every character is a tile you define in CHR-ROM
- Common convention: tile $00 = 'A', tile $01 = 'B', etc.
- ca65 lets you define a custom charmap:

```asm
.charmap 'A', $00
.charmap 'B', $01

.byte "HELLO"   ; compiles to tile indices, not ASCII
```
