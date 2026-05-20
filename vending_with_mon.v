/* 
   Derived from: vending/vending.v
   Purpose     : Add property/monitor outputs for BDD-based verification (LN).
*/

// Service Types
`define SERVICE_OFF     2'b00  // vending machine outputs items and changes
`define SERVICE_ON      2'b01  // vending machine waits external requests
`define SERVICE_BUSY    2'b10  // vending machine processes requests
// Coin Types
`define COIN_A          2'b00
`define COIN_B          2'b01
`define COIN_C          2'b10
`define COIN_D          2'b11
// Coin Values
`define VALUE_COIN_A    13'd50
`define VALUE_COIN_B    13'd10
`define VALUE_COIN_C    13'd5
`define VALUE_COIN_D    13'd1
// Item Types
`define ITEM_A          2'b00
`define ITEM_B          2'b01
`define ITEM_C          2'b10
`define ITEM_D          2'b11
// Item Costs
`define COST_ITEM_A     13'd15
`define COST_ITEM_B     13'd25
`define COST_ITEM_C     13'd75
`define COST_ITEM_D     13'd100

module vendingMachineWithMon(
   // General I/O Ports
   clk,
   reset,
   // Input Ports
   coinInA,
   coinInB,
   coinInC,
   coinInD,
   itemTypeIn,
   itemNumberIn,
   forceIn,
   // Output Ports
   coinOutA,
   coinOutB,
   coinOutC,
   coinOutD,
   itemTypeOut,
   itemNumberOut,
   serviceTypeOut,
   // Property / Monitor Outputs (1 = violation)
   p_underflow_item,
   p_illegal_service_state
);

input          clk;
input          reset;

input  [5:0]   coinInA;
input  [5:0]   coinInB;
input  [5:0]   coinInC;
input  [5:0]   coinInD;
input  [1:0]   itemTypeIn;
input  [2:0]   itemNumberIn;
input          forceIn;

output [5:0]   coinOutA;
output [5:0]   coinOutB;
output [5:0]   coinOutC;
output [5:0]   coinOutD;
output [1:0]   itemTypeOut;
output [2:0]   itemNumberOut;
output [1:0]   serviceTypeOut;

output         p_underflow_item;
output         p_illegal_service_state;

reg    [5:0]   coinOutA;
reg    [5:0]   coinOutB;
reg    [5:0]   coinOutC;
reg    [5:0]   coinOutD;
reg    [1:0]   itemTypeOut;
reg    [2:0]   itemNumberOut;
reg    [1:0]   serviceTypeOut;
reg            forceService;

reg    [5:0]   countA;
reg    [5:0]   countB;
reg    [5:0]   countC;
reg    [5:0]   countD;

reg    [12:0]  inputValue;
reg    [12:0]  serviceValue;

reg    [1:0]   serviceCoinType;
reg            changeReady;
reg            initialized;

// -------------------------
// Monitors (combinational)
// -------------------------
// Illegal service type encoding (should never be 2'b11).
assign p_illegal_service_state = (serviceTypeOut == 2'b11);

// Potential underflow hazard: in SERVICE_BUSY, if forceService keeps decrementing
// while itemNumberOut already 0 and inputValue < serviceValue, the next cycle would
// compute itemNumberOut - 1 (wraparound). Flag such states as violations.
assign p_underflow_item =
    (serviceTypeOut == `SERVICE_BUSY) &&
    (!changeReady) &&
    (inputValue < serviceValue) &&
    (forceService) &&
    (itemNumberOut == 3'd0);

always @ (posedge clk) begin
   if (!reset) begin
      coinOutA          <= 6'd0;
      coinOutB          <= 6'd0;
      coinOutC          <= 6'd0;
      coinOutD          <= 6'd0;
      itemTypeOut       <= `ITEM_A;
      itemNumberOut     <= 3'd0;
      serviceTypeOut    <= `SERVICE_ON;
      forceService      <= 1'b0;
      countA            <= 6'd5;
      countB            <= 6'd30;
      countC            <= 6'd10;
      countD            <= 6'd20;
      inputValue        <= 13'd0;
      serviceValue      <= 13'd0;
      serviceCoinType   <= 2'd0;
      changeReady       <= 1'b0;
      initialized       <= 1'b1;
   end
   else if (initialized) begin
      case (serviceTypeOut)
         `SERVICE_ON   : begin
            if (itemNumberIn != 3'd0) begin
               coinOutA          <= 6'd0;
               coinOutB          <= 6'd0;
               coinOutC          <= 6'd0;
               coinOutD          <= 6'd0;
               itemTypeOut       <= itemTypeIn;
               itemNumberOut     <= itemNumberIn;
               serviceTypeOut    <= `SERVICE_BUSY;
               forceService      <= forceIn;
               countA            <= (({1'b0, countA} + {1'b0, coinInA}) >= {1'b0, 6'b111111}) ? 6'b111111 : 
                                    (countA + coinInA);
               countB            <= (({1'b0, countB} + {1'b0, coinInB}) >= {1'b0, 6'b111111}) ? 6'b111111 : 
                                    (countB + coinInB);
               countC            <= (({1'b0, countC} + {1'b0, coinInC}) >= {1'b0, 6'b111111}) ? 6'b111111 : 
                                    (countC + coinInC);
               countD            <= (({1'b0, countD} + {1'b0, coinInD}) >= {1'b0, 6'b111111}) ? 6'b111111 : 
                                    (countD + coinInD);
               inputValue        <= (`VALUE_COIN_A * {7'd0, coinInA}) + 
                                    (`VALUE_COIN_B * {7'd0, coinInB}) + 
                                    (`VALUE_COIN_C * {7'd0, coinInC}) + 
                                    (`VALUE_COIN_D * {7'd0, coinInD});
               serviceValue      <= (itemTypeIn == `ITEM_A) ? ({10'd0, itemNumberIn} * `COST_ITEM_A) : 
                                    (itemTypeIn == `ITEM_B) ? ({10'd0, itemNumberIn} * `COST_ITEM_B) : 
                                    (itemTypeIn == `ITEM_C) ? ({10'd0, itemNumberIn} * `COST_ITEM_C) : 
                                    (itemTypeIn == `ITEM_D) ? ({10'd0, itemNumberIn} * `COST_ITEM_D) : 13'd0;
               serviceCoinType   <= `COIN_A;
               changeReady       <= 1'b0;
            end
         end
         `SERVICE_OFF  : begin
            serviceTypeOut <= `SERVICE_ON;
         end
         default       : begin
            if (!changeReady) begin
               if (inputValue < serviceValue) begin
                  if (forceService) begin
                     itemNumberOut <= itemNumberOut - 3'd1;
                     serviceValue  <= (itemTypeOut == `ITEM_A) ? (serviceValue - `COST_ITEM_A) : 
                                      (itemTypeOut == `ITEM_B) ? (serviceValue - `COST_ITEM_B) : 
                                      (itemTypeOut == `ITEM_C) ? (serviceValue - `COST_ITEM_C) : 
                                      (itemTypeOut == `ITEM_D) ? (serviceValue - `COST_ITEM_D) : 13'd0;
                  end
                  else begin
                     changeReady   <= 1'b1;
                     serviceValue  <= inputValue;
                     itemNumberOut <= 3'd0;
                  end
               end
               else begin
                  changeReady   <= 1'b1;
                  serviceValue  <= inputValue - serviceValue;
               end
            end
            else begin
               case (serviceCoinType)
                  `COIN_A : begin
                     if (serviceValue >= `VALUE_COIN_A) begin
                        if (countA == 6'd0) begin
                           serviceCoinType <= `COIN_B;
                        end
                        else begin
                           coinOutA <= coinOutA + 6'd1;
                           countA <= countA - 6'd1;
                           serviceValue <= serviceValue - `VALUE_COIN_A;
                        end
                     end
                     else begin
                        serviceCoinType <= `COIN_B;
                     end
                  end
                  `COIN_B : begin
                     if (serviceValue >= `VALUE_COIN_B) begin
                        if (countB == 6'd0) begin
                           serviceCoinType <= `COIN_C;
                        end
                        else begin
                           coinOutB <= coinOutB + 6'd1;
                           countB <= countB - 6'd1;
                           serviceValue <= serviceValue - `VALUE_COIN_B;
                        end
                     end
                     else begin
                        serviceCoinType <= `COIN_C;
                     end
                  end
                  `COIN_C  : begin
                     if (serviceValue >= `VALUE_COIN_C) begin
                        if (countC == 6'd0) begin
                           serviceCoinType <= `COIN_D;
                        end
                        else begin
                           coinOutC <= coinOutC + 6'd1;
                           countC <= countC - 6'd1;
                           serviceValue <= serviceValue - `VALUE_COIN_C;
                        end
                     end
                     else begin
                        serviceCoinType <= `COIN_D;
                     end
                  end
                  `COIN_D  : begin
                     if (serviceValue >= `VALUE_COIN_D) begin
                        if (countD == 6'd0) begin
                           coinOutA          <= 6'd0;
                           coinOutB          <= 6'd0;
                           coinOutC          <= 6'd0;
                           coinOutD          <= 6'd0;
                           countA            <= (countA + coinOutA);
                           countB            <= (countB + coinOutB);
                           countC            <= (countC + coinOutC);
                           countD            <= (countD + coinOutD);
                           serviceCoinType   <= `COIN_A;
                           if (forceService) begin
                              itemNumberOut     <= itemNumberOut - 3'd1;
                              serviceValue      <= (`VALUE_COIN_A * {7'd0, coinOutA}) + 
                                                   (`VALUE_COIN_B * {7'd0, coinOutB}) + 
                                                   (`VALUE_COIN_C * {7'd0, coinOutC}) + 
                                                   (`VALUE_COIN_D * {7'd0, coinOutD}) + 
                                                   serviceValue + (
                                                   (itemTypeOut == `ITEM_A) ? `COST_ITEM_A : 
                                                   (itemTypeOut == `ITEM_B) ? `COST_ITEM_B : 
                                                   (itemTypeOut == `ITEM_C) ? `COST_ITEM_C : 
                                                   (itemTypeOut == `ITEM_D) ? `COST_ITEM_D : 13'd0);
                           end
                           else begin
                              serviceValue   <= inputValue;
                              itemNumberOut  <= 3'd0;
                           end
                        end
                        else begin
                           coinOutD <= coinOutD + 6'd1;
                           countD <= countD - 6'd1;
                           serviceValue <= serviceValue - `VALUE_COIN_D;
                        end
                     end
                     else begin
                        serviceTypeOut <= `SERVICE_OFF;
                     end
                  end
               endcase
            end
         end
      endcase
   end
end

endmodule

