`timescale 1ns/1ps
// Single-cycle 64-bit processor (RV64I subset) - top-level datapath
module rv64_top #(parameter IMEM_INIT = "program.hex") (
    input  wire        clk,
    input  wire        rst,
    // program loader port (tie to 0 in simulation)
    input  wire        imem_we,
    input  wire [7:0]  imem_waddr,
    input  wire [31:0] imem_wdata,
    output wire [63:0] pc_out,
    output wire [31:0] instr_out,
    output wire [63:0] alu_out
);
    wire [63:0] pc, pc_plus4, imm, rd1, rd2, alu_b, alu_result, mem_rd, wb_data;
    wire [31:0] instr;
    wire        reg_write, alu_src, mem_read, mem_write, branch, jump, jalr, br_cond, zero;
    wire [1:0]  wb_sel;
    wire [3:0]  alu_ctrl;

    pc_unit u_pc (.clk(clk), .rst(rst), .branch_taken(branch & br_cond), .jump(jump),
                  .jalr(jalr), .imm(imm), .alu_result(alu_result), .pc(pc), .pc_plus4(pc_plus4));

    imem #(.INIT(IMEM_INIT)) u_imem (.clk(clk), .we(imem_we), .waddr(imem_waddr),
                                  .wdata(imem_wdata), .addr(pc), .instr(instr));

    control u_ctrl (.opcode(instr[6:0]), .funct3(instr[14:12]), .funct7_5(instr[30]),
                    .reg_write(reg_write), .alu_src(alu_src), .mem_read(mem_read),
                    .mem_write(mem_write), .wb_sel(wb_sel), .branch(branch), .jump(jump),
                    .jalr(jalr), .alu_ctrl(alu_ctrl));

    regfile_64 u_rf (.clk(clk), .rst(rst), .we(reg_write), .rs1(instr[19:15]),
                     .rs2(instr[24:20]), .rd(instr[11:7]), .wd(wb_data), .rd1(rd1), .rd2(rd2));

    imm_gen u_imm (.instr(instr), .imm(imm));

    assign alu_b = alu_src ? imm : rd2;
    alu_64 u_alu (.a(rd1), .b(alu_b), .alu_ctrl(alu_ctrl), .result(alu_result), .zero(zero));

    branch_unit u_br (.a(rd1), .b(rd2), .funct3(instr[14:12]), .taken(br_cond));

    dmem u_dmem (.clk(clk), .we(mem_write), .re(mem_read), .addr(alu_result), .wd(rd2), .rd(mem_rd));

    assign wb_data = (wb_sel == 2'd0) ? alu_result :
                     (wb_sel == 2'd1) ? mem_rd     :
                     (wb_sel == 2'd2) ? pc_plus4   : imm;

    assign pc_out = pc; assign instr_out = instr; assign alu_out = alu_result;
endmodule
