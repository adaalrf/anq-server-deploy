{
  serviceName = "vrising";
  ports = {
    udp = [
      9876
      9877
    ];
    udpOptional = [ ];
    tcp = [ ];
    tcpOptional = [ ];
  };
  logPattern = "Started V Rising dedicated server";
}
