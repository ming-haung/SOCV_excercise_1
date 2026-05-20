/*
  Register-cut over-approximation for BDD verification.
  - Keep control + arithmetic registers: inputValue, serviceValue, serviceTypeOut,
    itemNumberOut, itemTypeOut, forceService, changeReady, initialized.
  - Cut inventory / change-making state to free primary inputs (each cycle):
    countA-D, serviceCoinType, coinOutA-D (referenced in a tautology guard).
  - SERVICE_BUSY change loop: endChangeIn PI can finish change (over-approx).
*/

`define SERVICE_OFF     2'b00
`define SERVICE_ON      2'b01
`define SERVICE_BUSY    2'b10
`define ITEM_A          2'b00
`define ITEM_B          2'b01
`define ITEM_C          2'b10
`define ITEM_D          2'b11
`define VALUE_COIN_A    13'd50
`define VALUE_COIN_B    13'd10
`define VALUE_COIN_C    13'd5
`define VALUE_COIN_D    13'd1
`define COST_ITEM_A     13'd15
`define COST_ITEM_B     13'd25
`define COST_ITEM_C     13'd75
`define COST_ITEM_D     13'd100

module vendingMachineAbsRegcutWithMon(
   clk,
   reset,
   coinInA,
   coinInB,
   coinInC,
   coinInD,
   itemTypeIn,
   itemNumberIn,
   forceIn,
   endChangeIn,
   countAIn,
   countBIn,
   countCIn,
   countDIn,
   serviceCoinTypeIn,
   coinOutAIn,
   coinOutBIn,
   coinOutCIn,
   coinOutDIn,
   itemTypeOut,
   itemNumberOut,
   serviceTypeOut,
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
input          endChangeIn;
input  [5:0]   countAIn;
input  [5:0]   countBIn;
input  [5:0]   countCIn;
input  [5:0]   countDIn;
input  [1:0]   serviceCoinTypeIn;
input  [5:0]   coinOutAIn;
input  [5:0]   coinOutBIn;
input  [5:0]   coinOutCIn;
input  [5:0]   coinOutDIn;

output [1:0]   itemTypeOut;
output [2:0]   itemNumberOut;
output [1:0]   serviceTypeOut;
output         p_underflow_item;
output         p_illegal_service_state;

reg    [1:0]   itemTypeOut;
reg    [2:0]   itemNumberOut;
reg    [1:0]   serviceTypeOut;
reg            forceService;
reg    [12:0]  inputValue;
reg    [12:0]  serviceValue;
reg            changeReady;
reg            initialized;

wire inventory_tie =
    |countAIn | |countBIn | |countCIn | |countDIn |
    |coinOutAIn | |coinOutBIn | |coinOutCIn | |coinOutDIn |
    |serviceCoinTypeIn;

assign p_illegal_service_state = (serviceTypeOut == 2'b11);
assign p_underflow_item =
    (serviceTypeOut == `SERVICE_BUSY) &&
    (!changeReady) &&
    (inputValue < serviceValue) &&
    (forceService) &&
    (itemNumberOut == 3'd0);

always @(posedge clk) begin
   if (!reset) begin
      itemTypeOut       <= `ITEM_A;
      itemNumberOut     <= 3'd0;
      serviceTypeOut    <= `SERVICE_ON;
      forceService      <= 1'b0;
      inputValue        <= 13'd0;
      serviceValue      <= 13'd0;
      changeReady       <= 1'b0;
      initialized       <= 1'b1;
   end
   else if (initialized) begin
      case (serviceTypeOut)
         `SERVICE_ON: begin
            if (itemNumberIn != 3'd0) begin
               itemTypeOut    <= itemTypeIn;
               itemNumberOut  <= itemNumberIn;
               serviceTypeOut <= `SERVICE_BUSY;
               forceService   <= forceIn;
               inputValue     <= (`VALUE_COIN_A * {7'd0, coinInA}) +
                                 (`VALUE_COIN_B * {7'd0, coinInB}) +
                                 (`VALUE_COIN_C * {7'd0, coinInC}) +
                                 (`VALUE_COIN_D * {7'd0, coinInD});
               serviceValue   <= (itemTypeIn == `ITEM_A) ? ({10'd0, itemNumberIn} * `COST_ITEM_A) :
                                 (itemTypeIn == `ITEM_B) ? ({10'd0, itemNumberIn} * `COST_ITEM_B) :
                                 (itemTypeIn == `ITEM_C) ? ({10'd0, itemNumberIn} * `COST_ITEM_C) :
                                 (itemTypeIn == `ITEM_D) ? ({10'd0, itemNumberIn} * `COST_ITEM_D) : 13'd0;
               changeReady    <= 1'b0;
            end
         end
         `SERVICE_OFF: begin
            serviceTypeOut <= `SERVICE_ON;
         end
         default: begin
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
            else if (endChangeIn | inventory_tie) begin
               serviceTypeOut <= `SERVICE_OFF;
            end
         end
      endcase
   end
end

endmodule
