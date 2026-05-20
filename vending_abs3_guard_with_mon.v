/*
  Ultra-light abstraction (guard abstraction) for BDD reachability.
  Replace wide arithmetic (inputValue/serviceValue and comparisons) with 1-bit guards.

  Inputs:
    - reqIn:   whether there is a valid request (itemNumberIn != 0)
    - lessIn:  abstraction of (inputValue < serviceValue) in SERVICE_BUSY before changeReady
    - forceIn: same meaning as original (force service as much as possible)

  State:
    - serviceTypeOut (ON/BUSY/OFF)
    - itemNumberOut (2-bit)
    - forceService (latched)
    - changeReady

  Monitors:
    - p_underflow_item: flags reachable states where itemNumberOut==0 but machine would still
      attempt to decrement under forceService with lessIn asserted.
    - p_illegal_service_state: invalid service encoding (should never happen).
*/

`define SERVICE_OFF     2'b00
`define SERVICE_ON      2'b01
`define SERVICE_BUSY    2'b10

module vendingMachineAbs3WithMon(
  clk,
  reset,
  // abstract inputs
  reqIn,
  lessIn,
  forceIn,
  itemNumberIn,
  // outputs
  serviceTypeOut,
  itemNumberOut,
  // monitors
  p_underflow_item,
  p_illegal_service_state
);

input        clk;
input        reset;
input        reqIn;
input        lessIn;
input        forceIn;
input  [1:0] itemNumberIn;

output [1:0] serviceTypeOut;
output [1:0] itemNumberOut;
output       p_underflow_item;
output       p_illegal_service_state;

reg    [1:0] serviceTypeOut;
reg    [1:0] itemNumberOut;
reg          forceService;
reg          changeReady;

assign p_illegal_service_state = (serviceTypeOut == 2'b11);

assign p_underflow_item =
  (serviceTypeOut == `SERVICE_BUSY) &&
  (!changeReady) &&
  (lessIn) &&
  (forceService) &&
  (itemNumberOut == 2'd0);

always @(posedge clk) begin
  if (!reset) begin
    serviceTypeOut <= `SERVICE_ON;
    itemNumberOut  <= 2'd0;
    forceService   <= 1'b0;
    changeReady    <= 1'b0;
  end else begin
    case (serviceTypeOut)
      `SERVICE_ON: begin
        if (reqIn) begin
          serviceTypeOut <= `SERVICE_BUSY;
          itemNumberOut  <= itemNumberIn;
          forceService   <= forceIn;
          changeReady    <= 1'b0;
        end
      end
      `SERVICE_OFF: begin
        serviceTypeOut <= `SERVICE_ON;
      end
      default: begin // BUSY
        if (!changeReady) begin
          if (lessIn) begin
            if (forceService) begin
              itemNumberOut <= itemNumberOut - 2'd1;
            end else begin
              changeReady   <= 1'b1;
              itemNumberOut <= 2'd0;
            end
          end else begin
            changeReady <= 1'b1;
          end
        end else begin
          serviceTypeOut <= `SERVICE_OFF;
        end
      end
    endcase
  end
end

endmodule

