// This file is part of www.nand2tetris.org
// and the book "The Elements of Computing Systems"
// by Nisan and Schocken, MIT Press.
// File name: projects/4/Fill.asm

// Runs an infinite loop that listens to the keyboard input. 
// When a key is pressed (any key), the program blackens the screen,
// i.e. writes "black" in every pixel. When no key is pressed, 
// the screen should be cleared.

(IDLE_LOOP) // poll @KBD until a key is pressed
  @KBD
  D=M
  @IDLE_LOOP
  D;JEQ

  @color
  M=-1 // -1 = 0xffff = 16 black pixels
  @KEYPRESS_LOOP // set the return address to enter the keypress loop
  D=A
  @ra
  M=D
  @SET_SCREEN
  0;JMP

  (KEYPRESS_LOOP) // poll @KBD until the key is released
    @KBD
    D=M
    @KEYPRESS_LOOP
    D;JNE

  @color // key was released, clear the screen (0 = 0x0000 = 16 white pixels) and...
  M=0
  @IDLE_LOOP // ...return to the idle loop
  D=A
  @ra
  M=D
  @SET_SCREEN
  0;JMP

(SET_SCREEN)
  @SCREEN
  D=A
  @addr // set the base address to the screen MMIO address
  M=D

  @8192 // the screen is 256x512 pixels, which is 8192 16-bit words
  D=A
  @i
  M=D

  (SET_PIXEL_LOOP) // set each 16-bit word in the screen to the current color (black or white)
    @color
    D=M

    @addr
    A=M
    M=D

    @addr
    M=M+1

    @i
    MD=M-1
    @SET_PIXEL_LOOP
    D;JGT

  @ra
  A=M // return to the stored return address (either IDLE_LOOP or KEYPRESS_LOOP)
  0;JMP
