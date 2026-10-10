import TaktCLI

/// The `takt` executable; the commands live in `TaktCLI`, so they can be tested.
@main
enum Takt {
  static func main() async {
    await TaktCommand.main()
  }
}
