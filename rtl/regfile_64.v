`timescale 1ns/1ps
// 32 x 64-bit register file: 2 async read ports, 1 sync write port, x0 = 0
module regfile_64 (
    input  wire        clk,
    input  wire        rst,
    input  wire        we,
    input  wire [4:0]  rs1, rs2, rd,
    input  wire [63:0] wd,
    output wire [63:0] rd1, rd2
);
    reg [63:0] regs [0:31];
    integer i;
    always @(posedge clk) begin
        if (rst) begin
            for (i = 0; i < 32; i = i + 1) regs[i] <= 64'd0;
        end else if (we && rd != 5'd0) begin
            regs[rd] <= wd;
        end
    end
    assign rd1 = (rs1 == 5'd0) ? 64'd0 : regs[rs1];
    assign rd2 = (rs2 == 5'd0) ? 64'd0 : regs[rs2];
endmodule
