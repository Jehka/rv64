`timescale 1ns/1ps
// Main control unit + ALU decoder
module control (
    input  wire [6:0] opcode,
    input  wire [2:0] funct3,
    input  wire       funct7_5,     // instr[30]
    output reg        reg_write,
    output reg        alu_src,      // 0: rs2, 1: imm
    output reg        mem_read,
    output reg        mem_write,
    output reg  [1:0] wb_sel,       // 0: ALU, 1: MEM, 2: PC+4, 3: IMM
    output reg        branch,
    output reg        jump,         // jal
    output reg        jalr,
    output reg  [3:0] alu_ctrl
);
    localparam OP_R=7'b0110011, OP_I=7'b0010011, OP_LD=7'b0000011, OP_ST=7'b0100011,
               OP_BR=7'b1100011, OP_JAL=7'b1101111, OP_JALR=7'b1100111, OP_LUI=7'b0110111;
    localparam ADD=4'd0, SUB=4'd1, AND=4'd2, OR=4'd3, XOR=4'd4,
               SLT=4'd5, SLTU=4'd6, SLL=4'd7, SRL=4'd8, SRA=4'd9;

    reg [1:0] alu_op;   // 00: add, 10: R-type, 11: I-type ALU

    // main decoder
    always @(*) begin
        {reg_write, alu_src, mem_read, mem_write, branch, jump, jalr} = 7'b0;
        wb_sel = 2'd0; alu_op = 2'b00;
        case (opcode)
            OP_R:    begin reg_write=1; alu_op=2'b10; end
            OP_I:    begin reg_write=1; alu_src=1; alu_op=2'b11; end
            OP_LD:   begin reg_write=1; alu_src=1; mem_read=1; wb_sel=2'd1; end
            OP_ST:   begin alu_src=1; mem_write=1; end
            OP_BR:   begin branch=1; end
            OP_JAL:  begin reg_write=1; jump=1; wb_sel=2'd2; end
            OP_JALR: begin reg_write=1; alu_src=1; jalr=1; wb_sel=2'd2; end
            OP_LUI:  begin reg_write=1; wb_sel=2'd3; end
            default: ;
        endcase
    end

    // ALU decoder
    always @(*) begin
        case (alu_op)
            2'b10, 2'b11: case (funct3)
                3'b000: alu_ctrl = (alu_op==2'b10 && funct7_5) ? SUB : ADD;
                3'b001: alu_ctrl = SLL;
                3'b010: alu_ctrl = SLT;
                3'b011: alu_ctrl = SLTU;
                3'b100: alu_ctrl = XOR;
                3'b101: alu_ctrl = funct7_5 ? SRA : SRL;
                3'b110: alu_ctrl = OR;
                3'b111: alu_ctrl = AND;
            endcase
            default: alu_ctrl = ADD;
        endcase
    end
endmodule
