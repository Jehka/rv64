`timescale 1ns/1ps
// 64-bit ALU
module alu_64 (
    input  wire [63:0] a,
    input  wire [63:0] b,
    input  wire [3:0]  alu_ctrl,
    output reg  [63:0] result,
    output wire        zero
);
    localparam ADD=4'd0, SUB=4'd1, AND=4'd2, OR=4'd3, XOR=4'd4,
               SLT=4'd5, SLTU=4'd6, SLL=4'd7, SRL=4'd8, SRA=4'd9;

    always @(*) begin
        case (alu_ctrl)
            ADD : result = a + b;
            SUB : result = a - b;
            AND : result = a & b;
            OR  : result = a | b;
            XOR : result = a ^ b;
            SLT : result = {63'd0, ($signed(a) < $signed(b))};
            SLTU: result = {63'd0, (a < b)};
            SLL : result = a << b[5:0];
            SRL : result = a >> b[5:0];
            SRA : result = $signed(a) >>> b[5:0];
            default: result = 64'd0;
        endcase
    end
    assign zero = (result == 64'd0);
endmodule
