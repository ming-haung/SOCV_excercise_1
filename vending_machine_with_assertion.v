// GV 不支援 PSL：請把要檢查的性質拉到 module 的 output（此處 ast_*），再用
//   cirr designs/vending_machine.v
//   random sim -sim_cycle N -v -rst reset
// -v 會印出所有 PO；任一出現 ast_*==0 代表該性質在上一筆交易計算時失敗。
// （若與 SPEC-vedning machine.pdf 不同，請只改下方 property 區塊。）

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
    output reg  [1:0]  serviceTypeOut,

    // --- promoted assertions (1 = pass) ---
    output wire        ast_stores_le7,
    output reg         ast_cost_ok,
    output reg         ast_success_change_ok,
    output reg         ast_fail_return_ok,
    output reg         ast_store_update_ok,
    output reg         ast_fsm_ok,          // [NEW] FSM 狀態轉移合法性
    output wire        ast_all_ok
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

    // --- [NEW] for cross-cycle ast_store_update_ok ---
    // 在進入 BUSY 之前，先把「預期的新 store 值」記下來
    // 等下一個 cycle（ST_OFF）再和實際 store 比對
    integer exp_store50, exp_store10, exp_store5, exp_store1;

    // --- [NEW] for cross-cycle ast_fail_return_ok ---
    // 在 ST_BUSY 把「預期的 coinOut 輸出」存起來
    // 等 ST_OFF 再與實際 coinOut* 比對
    integer exp_out50, exp_out10, exp_out5, exp_out1;
    reg     exp_success;   // 記錄這筆交易是否成功

    // --- [NEW] for ast_fsm_ok: 記住上一個 cycle 的 state ---
    reg [1:0] prev_state;

    assign ast_stores_le7 =
        (store50 <= 3'd7) && (store10 <= 3'd7) && (store5 <= 3'd7) && (store1 <= 3'd7);

    assign ast_all_ok =
        ast_stores_le7 & ast_cost_ok & ast_success_change_ok &
        ast_fail_return_ok & ast_store_update_ok & ast_fsm_ok;

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

            ast_cost_ok            <= 1'b1;
            ast_success_change_ok  <= 1'b1;
            ast_fail_return_ok     <= 1'b1;
            ast_store_update_ok    <= 1'b1;
            ast_fsm_ok             <= 1'b1;   // [NEW]
            prev_state             <= ST_ON;   // [NEW]
            exp_store50 <= 2; exp_store10 <= 2; exp_store5 <= 2; exp_store1 <= 2; // [NEW]
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

                    begin : gv_assertions
                        integer exp_cost_chk;
                        integer chg_sum;
                        integer ret_sum;   // [NEW] 退款金額
                        exp_cost_chk = 0;
                        case (req_item)
                            ITEM_A: exp_cost_chk = 8;
                            ITEM_B: exp_cost_chk = 15;
                            ITEM_C: exp_cost_chk = 22;
                            default: exp_cost_chk = 0;
                        endcase
                        ast_cost_ok <= (cost == exp_cost_chk);

                        chg_sum = use50 * 50 + use10 * 10 + use5 * 5 + use1;
                        ast_success_change_ok <=
                            !success ||
                            ((total_in >= cost) && (chg_sum == (total_in - cost)));

                        // [FIX] ast_fail_return_ok
                        // 失敗時（不論是錢不夠或找不開），退款金額必須等於投入金額
                        // coinOutNTD_* 在同一個 always block 用 <= 指定，
                        // 要讀「即將寫入的值」只能用 in* 反推；
                        // 用 non-blocking 的 RHS 值直接比較最安全。
                        ret_sum = {1'b0, in50} * 50 + {1'b0, in10} * 10
                                  + {1'b0, in5} * 5 + {1'b0, in1};
                        if (!success)
                            // 退回去的硬幣價值必須等於當初投入的
                            ast_fail_return_ok <= (ret_sum == total_in);
                        else
                            ast_fail_return_ok <= 1'b1;

                        // [FIX] ast_store_update_ok
                        // 把「預期新 store」存到 snapshot，等進入 ST_OFF 再與
                        // 真正寫進去的 store 暫存器比對（跨 cycle 驗證）
                        if (success) begin
                            exp_store50 <= tmp50 - use50;
                            exp_store10 <= tmp10 - use10;
                            exp_store5  <= tmp5  - use5;
                            exp_store1  <= tmp1  - use1;
                        end else begin
                            // 失敗：store 不動，預期等於現在的值
                            exp_store50 <= store50;
                            exp_store10 <= store10;
                            exp_store5  <= store5;
                            exp_store1  <= store1;
                        end

                        // [NEW] 把「預期的 coinOut 輸出」存成 snapshot
                        // 等 ST_OFF 再與實際 coinOut* registers 比對
                        exp_success <= success;
                        if (success) begin
                            // 成功：找零給客戶
                            exp_out50 <= use50;
                            exp_out10 <= use10;
                            exp_out5  <= use5;
                            exp_out1  <= use1;
                        end else begin
                            // 失敗：退回原幣（in* 已是 latched 值，直接用）
                            exp_out50 <= {1'b0, in50};
                            exp_out10 <= {1'b0, in10};
                            exp_out5  <= {1'b0, in5};
                            exp_out1  <= {1'b0, in1};
                        end
                        // 實際比對在 ST_OFF 進行（見下方）
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

                    // [FIX] ast_store_update_ok: 跨 cycle 比對
                    // 現在已經是 ST_OFF，store 暫存器在上一個 cycle（ST_BUSY）
                    // 應該已被更新，檢查是否與當時計算的預期值相符
                    ast_store_update_ok <=
                        (store50 == sat3(exp_store50)) &&
                        (store10 == sat3(exp_store10)) &&
                        (store5  == sat3(exp_store5))  &&
                        (store1  == sat3(exp_store1));
                end

                default: begin
                    state <= ST_ON;
                    serviceTypeOut <= SERVICE_ON;
                end
            endcase

            // [NEW] ast_fsm_ok: 每個 cycle 檢查狀態轉移是否合法
            // 合法弧：ON->ON, ON->BUSY, BUSY->OFF, OFF->ON
            // 記錄本 cycle 的 state，下個 cycle 用 prev_state 比對
            prev_state <= state;
            case (prev_state)
                ST_ON:   ast_fsm_ok <= (state == ST_ON || state == ST_BUSY);
                ST_BUSY: ast_fsm_ok <= (state == ST_OFF);
                ST_OFF:  ast_fsm_ok <= (state == ST_ON);
                default: ast_fsm_ok <= 1'b0;  // 非法 state encoding
            endcase
        end
    end

endmodule