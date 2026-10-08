`timescale 1ns/1ps
// Branch comparator: beq, bne, blt, bge, bltu, bgeu
module branch_unit (
    input  wire [63:0] a, b,
    input  wire [2:0]  funct3,
    output reg         taken
);
    always @(*) begin
        case (funct3)
            3'b000: taken = (a == b);
            3'b001: taken = (a != b);
            3'b100: taken = ($signed(a) <  $signed(b));
            3'b101: taken = ($signed(a) >= $signed(b));
            3'b110: taken = (a <  b);
            3'b111: taken = (a >= b);
            default: taken = 1'b0;
        endcase
    end
endmodule
