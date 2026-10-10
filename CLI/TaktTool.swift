import TaktCLI

/// `takt` inside the app bundle (`Takt.app/Contents/Helpers/takt`); the commands live in `TaktCLI`.
@main
enum TaktTool {
  static func main() async {
    await TaktCommand.main()
  }
}
