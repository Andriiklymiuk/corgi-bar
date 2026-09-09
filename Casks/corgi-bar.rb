# Homebrew cask for corgi-bar. Copy into the andriiklymiuk/homebrew-tools tap
# as Casks/corgi-bar.rb once a release exists, and fill the sha256:
#   curl -L -o corgi-bar.zip https://github.com/Andriiklymiuk/corgi-bar/releases/download/v0.1.0/corgi-bar.zip
#   shasum -a 256 corgi-bar.zip
cask "corgi-bar" do
  version "0.1.0"
  sha256 "REPLACE_WITH_SHA256_OF_THE_RELEASE_ZIP"

  url "https://github.com/Andriiklymiuk/corgi-bar/releases/download/v#{version}/corgi-bar.zip"
  name "corgi-bar"
  desc "Claude Code sessions in the macOS menu bar, from corgi's session board"
  homepage "https://github.com/Andriiklymiuk/corgi-bar"

  depends_on macos: :ventura

  app "corgi-bar.app"

  zap trash: [
    "~/Library/Preferences/com.andriiklymiuk.corgi-bar.plist",
  ]
end
