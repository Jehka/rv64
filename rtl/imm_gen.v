`timescale 1ns/1ps
// Immediate generator / sign extension (I, S, B, U, J formats)
module imm_gen (
    input  wire [31:0] instr,
    output reg  [63:0] imm
);
    wire [6:0] op = instr[6:0];
    always @(*) begin
        case (op)
            7'b0010011, 7'b0000011, 7'b1100111:   // I-type: ALU-imm, load, jalr
                imm = {{52{instr[31]}}, instr[31:20]};
            7'b0100011:                           // S-type: store
                imm = {{52{instr[31]}}, instr[31:25], instr[11:7]};
            7'b1100011:                           // B-type: branch
                imm = {{51{instr[31]}}, instr[31], instr[7], instr[30:25], instr[11:8], 1'b0};
            7'b0110111:                           // U-type: lui
                imm = {{32{instr[31]}}, instr[31:12], 12'd0};
            7'b1101111:                           // J-type: jal
                imm = {{43{instr[31]}}, instr[31], instr[19:12], instr[20], instr[30:21], 1'b0};
            default: imm = 64'd0;
        endcase
    end
endmodule
