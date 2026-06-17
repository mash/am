# Homebrew formula for `fm`.
#
# Canonical copy lives here; the tap (github.com/mash/homebrew-tap) installs a
# copy of this file under its Formula/ dir so `brew install mash/tap/fm` works.
# Head-only until the first tagged release — then add a `url`/`sha256` stable
# stanza pointing at the release tarball.
class Fm < Formula
  desc "Apple on-device Foundation Model from the command line"
  homepage "https://github.com/mash/fm"
  head "https://github.com/mash/fm.git", branch: "main"
  license "MIT"

  depends_on :macos
  depends_on xcode: ["26.0", :build]

  def install
    system "swift", "build", "--disable-sandbox", "-c", "release"
    bin.install ".build/release/fm"
  end

  test do
    assert_match "fm", shell_output("#{bin}/fm --version")
  end
end
