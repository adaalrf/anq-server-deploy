{
  serviceName = "service-name";
  ports = {
    udp = [12345];
    udpOptional = [];
    tcp = [];
    tcpOptional = [
      12346
      12347
    ];
  };

  logPattern = "Server started";
}
