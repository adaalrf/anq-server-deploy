{
  serviceName = "enshrouded";
  ports = {
    udp = [
      15636
      15637
      15638
    ];
    udpOptional = [ ];
    tcp = [ ];
    tcpOptional = [ ];
  };

  logPattern = "Started Enshrouded dedicated server";
}
