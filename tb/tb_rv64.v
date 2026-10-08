`timescale 1ns/1ps
// Self-checking testbench for the 64-bit single-cycle processor
module tb_rv64;
    reg clk = 0, rst = 1;
    wire [63:0] pc, alu;
    wire [31:0] instr;
    integer errors = 0, cycles = 0;

    rv64_top #(.IMEM_INIT("program.hex")) dut (.clk(clk), .rst(rst),
        .imem_we(1'b0), .imem_waddr(8'd0), .imem_wdata(32'd0),
        .pc_out(pc), .instr_out(instr), .alu_out(alu));

    always #5 clk = ~clk;   // 100 MHz

    task check(input [4:0] r, input [63:0] exp);
        begin
            if (dut.u_rf.regs[r] !== exp) begin
                $display("  FAIL x%0d = %h  (expected %h)", r, dut.u_rf.regs[r], exp);
                errors = errors + 1;
            end else
                $display("  PASS x%0d = %h", r, exp);
        end
    endtask

    initial begin
        $dumpfile("rv64.vcd");
        $dumpvars(0, tb_rv64);
        repeat (2) @(posedge clk);
        rst = 0;
        // run until the halt instruction (beq x0,x0,0) or timeout
        while (instr !== 32'h00000063 && cycles < 500) begin
            @(posedge clk); cycles = cycles + 1;
        end
        #1;
        $display("\nHalted at PC=%h after %0d cycles\n", pc, cycles);
        $display("-- Arithmetic / logical --");
        check(1, 64'd10);   check(2, 64'd3);    check(3, 64'd13);  check(4, 64'd7);
        check(5, 64'd2);    check(6, 64'd11);   check(7, 64'd9);   check(8, 64'd1);
        check(9, -64'sd1);  check(10, 64'd1);
        $display("-- Shifts (64-bit) --");
        check(11, 64'd80);  check(12, 64'h1FFF_FFFF_FFFF_FFFF);   check(13, -64'sd1);
        check(22, 64'd10 << 40); check(23, -64'sd1); check(30, 64'd20 << 40);
        $display("-- Load / store --");
        check(14, 64'd13);  check(15, -64'sd1);
        if (dut.u_dmem.mem[0] !== 64'd13 || dut.u_dmem.mem[1] !== {64{1'b1}}) begin
            $display("  FAIL dmem contents"); errors = errors + 1;
        end else $display("  PASS dmem[0]=13, dmem[1]=-1");
        $display("-- Branches / jumps --");
        check(16, 64'd0);   check(17, 64'd0);   check(18, 64'd10);
        check(20, 64'h64);  check(21, 64'd0);   check(28, 64'h84); check(29, 64'd0);
        $display("-- Immediates --");
        check(19, 64'h12345000); check(24, ~64'd10); check(25, 64'd2);
        check(26, 64'h7ff);      check(27, 64'h88);
        $display("\n%s  (%0d errors)\n", errors ? "*** TEST FAILED ***" : "*** ALL TESTS PASSED ***", errors);
        $finish;
    end

    // instruction trace
    always @(posedge clk) if (!rst)
        $display("t=%0t  PC=%h  instr=%h  alu=%h", $time, pc, instr, alu);
endmodule
