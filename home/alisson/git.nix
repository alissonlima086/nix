{ ... }:

{
  programs.git = {
    enable = true;

    settings = {
      user = {
        name = "Alisson Lima";
        email = "69772544+alissonlima086@users.noreply.github.com";
      };

      init.defaultBranch = "main";

      safe.directory = "/etc/nixos";
    };
  };
}
