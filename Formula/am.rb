# Homebrew formula for `am`.
#
# Canonical copy lives here; the tap (github.com/mash/homebrew-tap) installs a
# copy of this file under its Formula/ dir so `brew install mash/tap/am` works.
# Head-only until the first tagged release — then add a `url`/`sha256` stable
# stanza pointing at the release tarball.
class Am < Formula
  desc "Apple on-device Foundation Model from the command line"
  homepage "https://github.com/mash/am"
  head "https://github.com/mash/am.git", branch: "main"
  license "MIT"

  depends_on :macos
  depends_on xcode: ["26.0", :build]

  def install
    system "swift", "build", "--disable-sandbox", "-c", "release"
    bin.install ".build/release/am"
  end

  test do
    assert_match "am", shell_output("#{bin}/am --version")
  end
end
