`timescale 1ns/1ps
// Instruction memory: 32-bit words, word-aligned, async read.
// Write port = program loader; it also keeps synthesis from treating the
// memory as a constant ROM and trimming logic the test program never uses.
module imem #(parameter DEPTH = 256, parameter INIT = "program.hex") (
    input  wire                     clk,
    input  wire                     we,
    input  wire [$clog2(DEPTH)-1:0] waddr,
    input  wire [31:0]              wdata,
    input  wire [63:0]              addr,
    output wire [31:0]              instr
);
    reg [31:0] mem [0:DEPTH-1];
    integer i;
    initial begin
        for (i = 0; i < DEPTH; i = i + 1) mem[i] = 32'h00000013; // nop
        $readmemh(INIT, mem);
    end
    always @(posedge clk) if (we) mem[waddr] <= wdata;
    assign instr = mem[addr[$clog2(DEPTH)+1:2]];
endmodule
