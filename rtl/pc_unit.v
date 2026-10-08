`timescale 1ns/1ps
// Program counter + next-PC logic (instruction fetch address)
module pc_unit (
    input  wire        clk,
    input  wire        rst,
    input  wire        branch_taken,
    input  wire        jump,
    input  wire        jalr,
    input  wire [63:0] imm,
    input  wire [63:0] alu_result,   // rs1 + imm for jalr
    output reg  [63:0] pc,
    output wire [63:0] pc_plus4
);
    assign pc_plus4 = pc + 64'd4;
    wire [63:0] pc_target = pc + imm;
    wire [63:0] pc_next = jalr                    ? {alu_result[63:1], 1'b0} :
                          (jump | branch_taken)   ? pc_target :
                                                    pc_plus4;
    always @(posedge clk) begin
        if (rst) pc <= 64'd0;
        else     pc <= pc_next;
    end
endmodule
