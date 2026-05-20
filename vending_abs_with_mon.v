/* 
   Abstraction of vending/vending.v for BDD-based verification.
   - Reduce coin values and bit-widths to mitigate BDD blow-up.
   - Keep control structure (service state machine) similar.
   - Coin values: {A,B,C,D} = {5,3,2,1}
   - Item costs:  {A,B,C,D} = {2,3,5,6} (scaled-down)
*/

// Service Types
`define SERVICE_OFF     2'b00
`define SERVICE_ON      2'b01
`define SERVICE_BUSY    2'b10
// Coin Types
`define COIN_A          2'b00
`define COIN_B          2'b01
`define COIN_C          2'b10
`define COIN_D          2'b11
// Coin Values (abstracted)
`define VALUE_COIN_A    6'd5
`define VALUE_COIN_B    6'd3
`define VALUE_COIN_C    6'd2
`define VALUE_COIN_D    6'd1
// Item Types
`define ITEM_A          2'b00
`define ITEM_B          2'b01
`define ITEM_C          2'b10
`define ITEM_D          2'b11
// Item Costs (abstracted)
`define COST_ITEM_A     6'd2
`define COST_ITEM_B     6'd3
`define COST_ITEM_C     6'd5
`define COST_ITEM_D     6'd6

module vendingMachineAbsWithMon(
   clk,
   reset,
   coinInA,
   coinInB,
   coinInC,
   coinInD,
   itemTypeIn,
   itemNumberIn,
   forceIn,
   coinOutA,
   coinOutB,
   coinOutC,
   coinOutD,
   itemTypeOut,
   itemNumberOut,
   serviceTypeOut,
   p_underflow_item,
   p_illegal_service_state
);

input        clk;
input        reset;

// Abstract coin counts (0..3) instead of 0..63
input  [1:0] coinInA;
input  [1:0] coinInB;
input  [1:0] coinInC;
input  [1:0] coinInD;

input  [1:0] itemTypeIn;
input  [1:0] itemNumberIn;  // 0..3 items (abstract)
input        forceIn;

output [1:0] coinOutA;
output [1:0] coinOutB;
output [1:0] coinOutC;
output [1:0] coinOutD;
output [1:0] itemTypeOut;
output [1:0] itemNumberOut;
output [1:0] serviceTypeOut;

output       p_underflow_item;
output       p_illegal_service_state;

reg    [1:0] coinOutA;
reg    [1:0] coinOutB;
reg    [1:0] coinOutC;
reg    [1:0] coinOutD;
reg    [1:0] itemTypeOut;
reg    [1:0] itemNumberOut;
reg    [1:0] serviceTypeOut;
reg          forceService;

reg    [1:0] countA;
reg    [1:0] countB;
reg    [1:0] countC;
reg    [1:0] countD;

reg    [5:0] inputValue;
reg    [5:0] serviceValue;

reg    [1:0] serviceCoinType;
reg          changeReady;
reg          initialized;

assign p_illegal_service_state = (serviceTypeOut == 2'b11);
assign p_underflow_item =
    (serviceTypeOut == `SERVICE_BUSY) &&
    (!changeReady) &&
    (inputValue < serviceValue) &&
    (forceService) &&
    (itemNumberOut == 2'd0);

always @ (posedge clk) begin
   if (!reset) begin
      coinOutA        <= 2'd0;
      coinOutB        <= 2'd0;
      coinOutC        <= 2'd0;
      coinOutD        <= 2'd0;
      itemTypeOut     <= `ITEM_A;
      itemNumberOut   <= 2'd0;
      serviceTypeOut  <= `SERVICE_ON;
      forceService    <= 1'b0;
      countA          <= 2'd1;
      countB          <= 2'd2;
      countC          <= 2'd1;
      countD          <= 2'd2;
      inputValue      <= 6'd0;
      serviceValue    <= 6'd0;
      serviceCoinType <= `COIN_A;
      changeReady     <= 1'b0;
      initialized     <= 1'b1;
   end
   else if (initialized) begin
      case (serviceTypeOut)
         `SERVICE_ON   : begin
            if (itemNumberIn != 2'd0) begin
               coinOutA       <= 2'd0;
               coinOutB       <= 2'd0;
               coinOutC       <= 2'd0;
               coinOutD       <= 2'd0;
               itemTypeOut    <= itemTypeIn;
               itemNumberOut  <= itemNumberIn;
               serviceTypeOut <= `SERVICE_BUSY;
               forceService   <= forceIn;

               // saturate to 3
               countA <= ((countA + coinInA) > 2'd3) ? 2'd3 : (countA + coinInA);
               countB <= ((countB + coinInB) > 2'd3) ? 2'd3 : (countB + coinInB);
               countC <= ((countC + coinInC) > 2'd3) ? 2'd3 : (countC + coinInC);
               countD <= ((countD + coinInD) > 2'd3) ? 2'd3 : (countD + coinInD);

               inputValue <= (`VALUE_COIN_A * {4'd0, coinInA}) +
                             (`VALUE_COIN_B * {4'd0, coinInB}) +
                             (`VALUE_COIN_C * {4'd0, coinInC}) +
                             (`VALUE_COIN_D * {4'd0, coinInD});

               serviceValue <= (itemTypeIn == `ITEM_A) ? ({4'd0, itemNumberIn} * `COST_ITEM_A) :
                               (itemTypeIn == `ITEM_B) ? ({4'd0, itemNumberIn} * `COST_ITEM_B) :
                               (itemTypeIn == `ITEM_C) ? ({4'd0, itemNumberIn} * `COST_ITEM_C) :
                               (itemTypeIn == `ITEM_D) ? ({4'd0, itemNumberIn} * `COST_ITEM_D) : 6'd0;
               serviceCoinType <= `COIN_A;
               changeReady <= 1'b0;
            end
         end
         `SERVICE_OFF  : begin
            serviceTypeOut <= `SERVICE_ON;
         end
         default       : begin
            if (!changeReady) begin
               if (inputValue < serviceValue) begin
                  if (forceService) begin
                     itemNumberOut <= itemNumberOut - 2'd1;
                     serviceValue  <= (itemTypeOut == `ITEM_A) ? (serviceValue - `COST_ITEM_A) :
                                      (itemTypeOut == `ITEM_B) ? (serviceValue - `COST_ITEM_B) :
                                      (itemTypeOut == `ITEM_C) ? (serviceValue - `COST_ITEM_C) :
                                      (itemTypeOut == `ITEM_D) ? (serviceValue - `COST_ITEM_D) : 6'd0;
                  end
                  else begin
                     changeReady   <= 1'b1;
                     serviceValue  <= inputValue;
                     itemNumberOut <= 2'd0;
                  end
               end
               else begin
                  changeReady  <= 1'b1;
                  serviceValue <= inputValue - serviceValue;
               end
            end
            else begin
               case (serviceCoinType)
                  `COIN_A: begin
                     if (serviceValue >= `VALUE_COIN_A) begin
                        if (countA == 2'd0) serviceCoinType <= `COIN_B;
                        else begin
                           coinOutA <= coinOutA + 2'd1;
                           countA <= countA - 2'd1;
                           serviceValue <= serviceValue - `VALUE_COIN_A;
                        end
                     end
                     else serviceCoinType <= `COIN_B;
                  end
                  `COIN_B: begin
                     if (serviceValue >= `VALUE_COIN_B) begin
                        if (countB == 2'd0) serviceCoinType <= `COIN_C;
                        else begin
                           coinOutB <= coinOutB + 2'd1;
                           countB <= countB - 2'd1;
                           serviceValue <= serviceValue - `VALUE_COIN_B;
                        end
                     end
                     else serviceCoinType <= `COIN_C;
                  end
                  `COIN_C: begin
                     if (serviceValue >= `VALUE_COIN_C) begin
                        if (countC == 2'd0) serviceCoinType <= `COIN_D;
                        else begin
                           coinOutC <= coinOutC + 2'd1;
                           countC <= countC - 2'd1;
                           serviceValue <= serviceValue - `VALUE_COIN_C;
                        end
                     end
                     else serviceCoinType <= `COIN_D;
                  end
                  default: begin
                     if (serviceValue >= `VALUE_COIN_D) begin
                        if (countD == 2'd0) begin
                           // fail to return change => end service
                           coinOutA <= 2'd0;
                           coinOutB <= 2'd0;
                           coinOutC <= 2'd0;
                           coinOutD <= 2'd0;
                           serviceCoinType <= `COIN_A;
                           if (forceService) begin
                              itemNumberOut <= itemNumberOut - 2'd1;
                              serviceValue <= serviceValue + `COST_ITEM_A; // coarse recovery
                           end
                           else begin
                              serviceValue <= inputValue;
                              itemNumberOut <= 2'd0;
                           end
                        end
                        else begin
                           coinOutD <= coinOutD + 2'd1;
                           countD <= countD - 2'd1;
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

