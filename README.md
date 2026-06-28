# IP-ATTENTION-SCORE-CALCULATION-VERSION-
Thực hiện phép nhân matmul hai ma trận Q, K tính attention score được đóng gói thành ip với hai giao diện slave:  Slave0 thực hiện control quá trình compute, interface AXI Lite. Slave1 thực hiện nạp data Q, K vào BRAM q_ram, k_ram, interface AXI Lite.
