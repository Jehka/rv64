#!/usr/bin/env python3
"""Tiny RV64I-subset assembler for the PBL-2 test program -> program.hex"""
def r(f7,rs2,rs1,f3,rd,op): return (f7<<25)|(rs2<<20)|(rs1<<15)|(f3<<12)|(rd<<7)|op
def i(imm,rs1,f3,rd,op):    return ((imm&0xfff)<<20)|(rs1<<15)|(f3<<12)|(rd<<7)|op
def s(imm,rs2,rs1,f3,op):   return (((imm>>5)&0x7f)<<25)|(rs2<<20)|(rs1<<15)|(f3<<12)|((imm&0x1f)<<7)|op
def b(imm,rs2,rs1,f3):
    imm&=0x1fff
    return (((imm>>12)&1)<<31)|(((imm>>5)&0x3f)<<25)|(rs2<<20)|(rs1<<15)|(f3<<12)|(((imm>>1)&0xf)<<8)|(((imm>>11)&1)<<7)|0x63
def u(imm,rd,op): return ((imm&0xfffff)<<12)|(rd<<7)|op
def j(imm,rd):
    imm&=0x1fffff
    return (((imm>>20)&1)<<31)|(((imm>>1)&0x3ff)<<21)|(((imm>>11)&1)<<20)|(((imm>>12)&0xff)<<12)|(rd<<7)|0x6f

R,I,LD,ST,LUI,JALR=0x33,0x13,0x03,0x23,0x37,0x67
add =lambda rd,a,c:r(0,c,a,0,rd,R);   sub =lambda rd,a,c:r(0x20,c,a,0,rd,R)
and_=lambda rd,a,c:r(0,c,a,7,rd,R);   or_ =lambda rd,a,c:r(0,c,a,6,rd,R)
xor =lambda rd,a,c:r(0,c,a,4,rd,R);   slt =lambda rd,a,c:r(0,c,a,2,rd,R)
sltu=lambda rd,a,c:r(0,c,a,3,rd,R);   sll =lambda rd,a,c:r(0,c,a,1,rd,R)
srl =lambda rd,a,c:r(0,c,a,5,rd,R);   sra =lambda rd,a,c:r(0x20,c,a,5,rd,R)
addi=lambda rd,a,im:i(im,a,0,rd,I);   andi=lambda rd,a,im:i(im,a,7,rd,I)
ori =lambda rd,a,im:i(im,a,6,rd,I);   xori=lambda rd,a,im:i(im,a,4,rd,I)
slli=lambda rd,a,sh:i(sh,a,1,rd,I);   srai=lambda rd,a,sh:i(0x400|sh,a,5,rd,I)
ld  =lambda rd,off,a:i(off,a,3,rd,LD); sd=lambda rs,off,a:s(off,rs,a,3,ST)
beq =lambda a,c,o:b(o,c,a,0); bne=lambda a,c,o:b(o,c,a,1); blt=lambda a,c,o:b(o,c,a,4)
lui =lambda rd,im:u(im,rd,LUI); jal=lambda rd,o:j(o,rd)
jalr=lambda rd,a,o:i(o,a,0,rd,JALR)

prog = [
 addi(1,0,10),      # 00 x1  = 10
 addi(2,0,3),       # 04 x2  = 3
 add (3,1,2),       # 08 x3  = 13
 sub (4,1,2),       # 0c x4  = 7
 and_(5,1,2),       # 10 x5  = 2
 or_ (6,1,2),       # 14 x6  = 11
 xor (7,1,2),       # 18 x7  = 9
 slt (8,2,1),       # 1c x8  = 1
 addi(9,0,-1),      # 20 x9  = -1
 sltu(10,1,9),      # 24 x10 = 1
 sll (11,1,2),      # 28 x11 = 80
 srl (12,9,2),      # 2c x12 = 0x1FFF_FFFF_FFFF_FFFF
 sra (13,9,2),      # 30 x13 = -1
 sd  (3,0,0),       # 34 mem[0] = 13
 sd  (9,8,0),       # 38 mem[8] = -1
 ld  (14,0,0),      # 3c x14 = 13
 ld  (15,8,0),      # 40 x15 = -1
 beq (14,3,8),      # 44 taken -> skip next
 addi(16,0,99),     # 48 (skipped) x16 stays 0
 bne (1,2,8),       # 4c taken -> skip next
 addi(17,0,99),     # 50 (skipped) x17 stays 0
 addi(18,18,1),     # 54 loop: x18++
 blt (18,1,-4),     # 58 backward branch until x18 == 10
 lui (19,0x12345),  # 5c x19 = 0x12345000
 jal (20,8),        # 60 x20 = 0x64, jump to 0x68
 addi(21,0,99),     # 64 (skipped) x21 stays 0
 slli(22,1,40),     # 68 x22 = 10 << 40  (64-bit shift)
 srai(23,13,63),    # 6c x23 = -1
 xori(24,1,-1),     # 70 x24 = ~10
 andi(25,6,6),      # 74 x25 = 11 & 6 = 2
 ori (26,0,0x7ff),  # 78 x26 = 0x7ff
 addi(27,0,0x88),   # 7c x27 = 0x88 (jalr target)
 jalr(28,27,0),     # 80 x28 = 0x84, jump to 0x88
 addi(29,0,99),     # 84 (skipped) x29 stays 0
 add (30,22,22),    # 88 x30 = 20 << 40
 beq (0,0,0),       # 8c halt (self-loop)
]
with open("program.hex","w") as f:
    for w in prog: f.write(f"{w:08x}\n")
print(f"{len(prog)} instructions written")
