`timescale 1ns/1ps
// Data memory: 64-bit doublewords (ld/sd), async read, sync write
module dmem #(parameter DEPTH = 256) (
    input  wire        clk,
    input  wire        we,
    input  wire        re,
    input  wire [63:0] addr,
    input  wire [63:0] wd,
    output wire [63:0] rd
);
    reg [63:0] mem [0:DEPTH-1];
    integer i;
    initial for (i = 0; i < DEPTH; i = i + 1) mem[i] = 64'd0;
    wire [$clog2(DEPTH)-1:0] idx = addr[$clog2(DEPTH)+2:3];
    always @(posedge clk) if (we) mem[idx] <= wd;
    assign rd = re ? mem[idx] : 64'd0;
endmodule
