# Install: brew tap nezakoo/wakey https://github.com/nezakoo/wakey && brew install nezakoo/wakey/wakey
# url, version and sha256 are rewritten by tools/release.sh.
class Wakey < Formula
  desc "Menu-bar app that keeps the Mac awake, also while AI agents or a process run"
  homepage "https://github.com/nezakoo/wakey"
  url "https://github.com/nezakoo/wakey/releases/download/v0.0.0/wakey.tar.gz"
  version "0.0.0"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"
  license "MIT"

  depends_on macos: :ventura

  def install
    system "./build.sh"
    prefix.install "build/Wakey.app"
  end

  def caveats
    <<~EOS
      Start Wakey, and restart it after each upgrade:
        open #{opt_prefix}/Wakey.app
      To find it in Spotlight and Launchpad (after removing any other copy there):
        ln -s #{opt_prefix}/Wakey.app /Applications/Wakey.app
    EOS
  end

  test do
    assert_predicate prefix/"Wakey.app/Contents/MacOS/Wakey", :executable?
    assert_match "sfimage=eye", shell_output("#{prefix}/Wakey.app/Contents/Resources/wakey.sh")
  end
end
