{ ... }:

{
  fileSystems."/mnt/games" = {
    device = "/dev/disk/by-uuid/f12cacd1-32ab-4246-9c34-699674768a91";
    fsType = "ext4";
    options = [
      "nofail"
    ];
  };

  fileSystems."/mnt/hd" = {
    device = "/dev/disk/by-uuid/EE86D5D086D59983";
    fsType = "ntfs";
    options = [
      "uid=1000"
      "gid=100"
      "umask=022"
      "nofail"
    ];
  };
}
