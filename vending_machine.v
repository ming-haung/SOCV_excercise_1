module vending_machine (
    input  wire        clk,
    input  wire        reset,

    input  wire [1:0]  coinInNTD_50,
    input  wire [1:0]  coinInNTD_10,
    input  wire [1:0]  coinInNTD_5,
    input  wire [1:0]  coinInNTD_1,
    input  wire [1:0]  itemTypeIn,

    output reg  [2:0]  coinOutNTD_50,
    output reg  [2:0]  coinOutNTD_10,
    output reg  [2:0]  coinOutNTD_5,
    output reg  [2:0]  coinOutNTD_1,
    output reg  [1:0]  itemTypeOut,
    output reg  [1:0]  serviceTypeOut
);

    //============================================================
    // Parameter / Encoding
    //============================================================
    localparam ITEM_A    = 2'd0;   // 8 NTD
    localparam ITEM_B    = 2'd1;   // 15 NTD
    localparam ITEM_C    = 2'd2;   // 22 NTD
    localparam ITEM_NONE = 2'd3;

    localparam SERVICE_ON   = 2'd0;
    localparam SERVICE_BUSY = 2'd1;
    localparam SERVICE_OFF  = 2'd2;

    localparam ST_ON   = 2'd0;
    localparam ST_BUSY = 2'd1;
    localparam ST_OFF  = 2'd2;

    //============================================================
    // State / coin storage
    //============================================================
    reg [1:0] state;

    reg [2:0] store50, store10, store5, store1;

    // latched request during BUSY
    reg [1:0] req_item;
    reg [1:0] in50, in10, in5, in1;

    //============================================================
    // Internal variables
    //============================================================
    integer total_in;
    integer cost;
    integer change_amt;

    integer tmp50, tmp10, tmp5, tmp1;
    integer use50, use10, use5, use1;
    integer remain;

    integer new_store50, new_store10, new_store5, new_store1;

    reg success;

    // helper: saturate to 7
    function [2:0] sat3;
        input integer val;
        begin
            if (val < 0)
                sat3 = 3'd0;
            else if (val > 7)
                sat3 = 3'd7;
            else
                sat3 = val[2:0];
        end
    endfunction

    //============================================================
    // Sequential logic
    //============================================================
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= ST_ON;

            // spec: initially stores 2 coins for each type
            store50 <= 3'd2;
            store10 <= 3'd2;
            store5  <= 3'd2;
            store1  <= 3'd2;

            req_item <= ITEM_NONE;
            in50 <= 2'd0;
            in10 <= 2'd0;
            in5  <= 2'd0;
            in1  <= 2'd0;

            coinOutNTD_50 <= 3'd0;
            coinOutNTD_10 <= 3'd0;
            coinOutNTD_5  <= 3'd0;
            coinOutNTD_1  <= 3'd0;
            itemTypeOut   <= ITEM_NONE;
            serviceTypeOut <= SERVICE_ON;
        end
        else begin
            // default outputs for every cycle
            coinOutNTD_50 <= 3'd0;
            coinOutNTD_10 <= 3'd0;
            coinOutNTD_5  <= 3'd0;
            coinOutNTD_1  <= 3'd0;
            itemTypeOut   <= ITEM_NONE;

            case (state)
                //================================================
                // ON: wait for request
                //================================================
                ST_ON: begin
                    serviceTypeOut <= SERVICE_ON;

                    // request only accepted in SERVICE_ON and itemTypeIn != ITEM_NONE
                    if (itemTypeIn != ITEM_NONE) begin
                        req_item <= itemTypeIn;
                        in50 <= coinInNTD_50;
                        in10 <= coinInNTD_10;
                        in5  <= coinInNTD_5;
                        in1  <= coinInNTD_1;
                        state <= ST_BUSY;
                        serviceTypeOut <= SERVICE_BUSY;
                    end
                end

                //================================================
                // BUSY: calculate result
                //================================================
                ST_BUSY: begin
                    serviceTypeOut <= SERVICE_BUSY;

                    // total inserted money
                    total_in = in50 * 50 + in10 * 10 + in5 * 5 + in1;

                    // item cost
                    case (req_item)
                        ITEM_A: cost = 8;
                        ITEM_B: cost = 15;
                        ITEM_C: cost = 22;
                        default: cost = 0;
                    endcase

                    // first assume inserted coins are taken into machine
                    // with storage capped at 7
                    tmp50 = ((store50 + in50) > 7) ? 7 : (store50 + in50);
                    tmp10 = ((store10 + in10) > 7) ? 7 : (store10 + in10);
                    tmp5  = ((store5  + in5 ) > 7) ? 7 : (store5  + in5 );
                    tmp1  = ((store1  + in1 ) > 7) ? 7 : (store1  + in1 );

                    success = 1'b0;
                    use50 = 0;
                    use10 = 0;
                    use5  = 0;
                    use1  = 0;

                    if (total_in >= cost) begin
                        change_amt = total_in - cost;
                        remain = change_amt;

                        // greedy change making
                        use50 = (remain / 50);
                        if (use50 > tmp50) use50 = tmp50;
                        remain = remain - use50 * 50;

                        use10 = (remain / 10);
                        if (use10 > tmp10) use10 = tmp10;
                        remain = remain - use10 * 10;

                        use5 = (remain / 5);
                        if (use5 > tmp5) use5 = tmp5;
                        remain = remain - use5 * 5;

                        use1 = remain;
                        if (use1 > tmp1)
                            remain = -1;
                        else
                            remain = remain - use1;

                        if (remain == 0)
                            success = 1'b1;
                    end

                    if (success) begin
                        // successful request
                        coinOutNTD_50 <= use50[2:0];
                        coinOutNTD_10 <= use10[2:0];
                        coinOutNTD_5  <= use5[2:0];
                        coinOutNTD_1  <= use1[2:0];
                        itemTypeOut   <= req_item;

                        // update coin storage
                        new_store50 = tmp50 - use50;
                        new_store10 = tmp10 - use10;
                        new_store5  = tmp5  - use5;
                        new_store1  = tmp1  - use1;

                        store50 <= sat3(new_store50);
                        store10 <= sat3(new_store10);
                        store5  <= sat3(new_store5);
                        store1  <= sat3(new_store1);
                    end
                    else begin
                        // fail: return input coins, give nothing
                        // spec says no item or change not enough => ITEM_NONE
                        // and machine will never eat money
                        coinOutNTD_50 <= {1'b0, in50}; // 2-bit input expanded to 3-bit output
                        coinOutNTD_10 <= {1'b0, in10};
                        coinOutNTD_5  <= {1'b0, in5};
                        coinOutNTD_1  <= {1'b0, in1};
                        itemTypeOut   <= ITEM_NONE;

                        // storage unchanged
                        store50 <= store50;
                        store10 <= store10;
                        store5  <= store5;
                        store1  <= store1;
                    end

                    state <= ST_OFF;
                    serviceTypeOut <= SERVICE_OFF;
                end

                //================================================
                // OFF: output result for one cycle, then back ON
                //================================================
                ST_OFF: begin
                    serviceTypeOut <= SERVICE_OFF;
                    state <= ST_ON;
                end

                default: begin
                    state <= ST_ON;
                    serviceTypeOut <= SERVICE_ON;
                end
            endcase
        end
    end

endmodule
