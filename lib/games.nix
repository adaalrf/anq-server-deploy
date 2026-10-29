{
  palworld = {
    appId = "2394010";
    executable = "PalServer.sh";
    windows = false;
    settings = "server/Pal/Saved/Config/LinuxServer/PalWorldSettings.ini";
    backupPaths = [ "server/Pal/Saved" ];
    udpPorts = [ 8211 ];
  };
  enshrouded = {
    appId = "2278520";
    executable = "enshrouded_server.exe";
    windows = true;
    settings = "server/enshrouded_server.json";
    backupPaths = [
      "server/savegame"
      "server/enshrouded_server.json"
    ];
    udpPorts = [ 15637 ];
  };
  vrising = {
    appId = "1829350";
    executable = "VRisingServer.exe";
    windows = true;
    settings = "data/Settings/ServerHostSettings.json";
    backupPaths = [ "data" ];
    udpPorts = [
      9876
      9877
    ];
  };
}
