// ============================================================
//  Testbench: vending_machine
// ============================================================
`timescale 1ns/1ps

module tb_vending_machine;

// ---- DUT ports ----
reg        clk, reset;
reg  [1:0] coinInNTD_50, coinInNTD_10, coinInNTD_5, coinInNTD_1;
reg  [1:0] itemTypeIn;
wire [2:0] coinOutNTD_50, coinOutNTD_10, coinOutNTD_5, coinOutNTD_1;
wire [1:0] itemTypeOut;
wire [1:0] serviceTypeOut;

// ---- Item / Service constants ----
localparam ITEM_A    = 2'd0;
localparam ITEM_B    = 2'd1;
localparam ITEM_C    = 2'd2;
localparam ITEM_NONE = 2'd3;
localparam SERVICE_ON   = 2'd0;
localparam SERVICE_BUSY = 2'd1;
localparam SERVICE_OFF  = 2'd2;

// ---- DUT instantiation ----
vending_machine dut (
    .clk(clk), .reset(reset),
    .coinInNTD_50(coinInNTD_50), .coinInNTD_10(coinInNTD_10),
    .coinInNTD_5(coinInNTD_5),   .coinInNTD_1(coinInNTD_1),
    .itemTypeIn(itemTypeIn),
    .coinOutNTD_50(coinOutNTD_50), .coinOutNTD_10(coinOutNTD_10),
    .coinOutNTD_5(coinOutNTD_5),   .coinOutNTD_1(coinOutNTD_1),
    .itemTypeOut(itemTypeOut),
    .serviceTypeOut(serviceTypeOut)
);

// ---- Clock ----
initial clk = 0;
always #5 clk = ~clk;   // 100 MHz

// ---- Helper tasks ----
task clear_inputs;
begin
    coinInNTD_50 = 2'd0; coinInNTD_10 = 2'd0;
    coinInNTD_5  = 2'd0; coinInNTD_1  = 2'd0;
    itemTypeIn   = ITEM_NONE;
end
endtask

task wait_cycles;
    input integer n;
    integer i;
    begin
        for (i = 0; i < n; i = i+1) @(posedge clk);
    end
endtask

// ---- Print helper ----
task print_result;
    input [63:0] test_num;
    begin
        $display("--- Test %0d ---", test_num);
        $display("  serviceTypeOut = %0d  itemTypeOut = %0d",
                  serviceTypeOut, itemTypeOut);
        $display("  change: 50x%0d  10x%0d  5x%0d  1x%0d",
                  coinOutNTD_50, coinOutNTD_10, coinOutNTD_5, coinOutNTD_1);
    end
endtask

// ---- Stimulus ----
integer test;
initial begin
    $dumpfile("tb_vending_machine.vcd");
    $dumpvars(0, tb_vending_machine);

    // ===== RESET =====
    reset = 1; clear_inputs;
    wait_cycles(2);
    reset = 0;
    wait_cycles(1);

    // =========================================================
    // Test 1: Buy ITEM_A (cost 8) with exact 1x NTD_10
    //         Change expected: 2x NTD_1 ... wait, 10-8=2
    //         Actually 1x NTD_1 *2 = 2 NTD_1
    // =========================================================
    test = 1;
    coinInNTD_10 = 2'd1;   // insert 1 * 10 NT
    itemTypeIn   = ITEM_A;
    @(posedge clk); #1;    // ON -> BUSY latched
    clear_inputs;
    @(posedge clk); #1;    // BUSY: compute
    @(posedge clk); #1;    // OFF: output
    print_result(test);
    @(posedge clk); #1;    // back to ON

    // =========================================================
    // Test 2: Buy ITEM_B (cost 15) with 1x NTD_50
    //         Change: 35 NT -> 0x50 + 3x10 + 1x5 + 0x1
    //         (store has 2x10 initially so 2x10 + 1x5 + 10x1 – but store_1 only 2)
    //         Actually store after T1: 50->2,10->1(gave 0 back paid 1 got 0 chg),
    //         Hmm let's just observe
    // =========================================================
    test = 2;
    coinInNTD_50 = 2'd1;
    itemTypeIn   = ITEM_B;
    @(posedge clk); #1;
    clear_inputs;
    @(posedge clk); #1;
    @(posedge clk); #1;
    print_result(test);
    @(posedge clk); #1;

    // =========================================================
    // Test 3: Buy ITEM_C (cost 22) with 2x NTD_10 + 2x NTD_5
    //         Paid = 30, change = 8 -> 1x5 + 3x1
    // =========================================================
    test = 3;
    coinInNTD_10 = 2'd2;
    coinInNTD_5  = 2'd2;
    itemTypeIn   = ITEM_C;
    @(posedge clk); #1;
    clear_inputs;
    @(posedge clk); #1;
    @(posedge clk); #1;
    print_result(test);
    @(posedge clk); #1;

    // =========================================================
    // Test 4: Not enough money – insert 1x NTD_5 for ITEM_A (cost 8)
    //         Machine should return 5 NT, itemTypeOut = ITEM_NONE
    // =========================================================
    test = 4;
    coinInNTD_5 = 2'd1;
    itemTypeIn  = ITEM_A;
    @(posedge clk); #1;
    clear_inputs;
    @(posedge clk); #1;
    @(posedge clk); #1;
    print_result(test);
    @(posedge clk); #1;

    // =========================================================
    // Test 5: ITEM_NONE – machine stays in SERVICE_ON
    // =========================================================
    test = 5;
    coinInNTD_10 = 2'd1;
    itemTypeIn   = ITEM_NONE;
    @(posedge clk); #1;
    $display("--- Test %0d (should stay ON) ---", test);
    $display("  serviceTypeOut = %0d (expect %0d)", serviceTypeOut, SERVICE_ON);
    clear_inputs;
    @(posedge clk); #1;

    // =========================================================
    // Test 6: Insert exact cost for ITEM_A (1x NTD_5 + 3x NTD_1)
    //         Paid = 8, change = 0
    // =========================================================
    test = 6;
    coinInNTD_5 = 2'd1;
    coinInNTD_1 = 2'd3;
    itemTypeIn  = ITEM_A;
    @(posedge clk); #1;
    clear_inputs;
    @(posedge clk); #1;
    @(posedge clk); #1;
    print_result(test);
    @(posedge clk); #1;

    $display("===== Simulation complete =====");
    $finish;
end

endmodule
