# Project Zomboid Steam Parsers 🧟‍♂️🛠️

A suite of PowerShell tools designed for **Project Zomboid Server Admins** to streamline the management of Steam Workshop mods and collections.

These tools help you generate the necessary configuration lines (`Mods=...` and `WorkshopItems=...`) for your `servertest.ini` file, saving you hours of manual copy-pasting and formatting.

## 📂 Included Tools

### 1. [Mod Parser](./mod-parser/)
**Best for:** Analysis of specific tags and to create mod id lists.

*   **Input:** A list of Workshop IDs (text file).
*   **Output:** Detailed HTML report with tag highlighting (e.g., "Build 42", "Map").
*   **Config:** Generates `Mods=...` (internal IDs) and `WorkshopItems=...` lines.
*   **Smart:** Handles Steam API rate limiting and retries.

[👉 Go to Mod Parser Documentation](./mod-parser/README.MD)

### 2. [Collection Parser](./collection-parser/)
**Best for:** Extraction of workshop item ids from a Steam Collection.

*   **Input:** A Steam Workshop Collection ID.
*   **Output:** HTML report listing all mods in the collection.
*   **Config:** Generates the `WorkshopItems=...` line.
*   *Note:* Does not extract internal Mod IDs (requires use of Mod Parser).

[👉 Go to Collection Parser Documentation](./collection-parser/README.md)

## 📋 Requirements

*   **OS:** Windows 10/11
*   **PowerShell:** Version 5.1 or newer
*   **Internet:** Required to scrape Steam Workshop pages.

## 🤝 Contributing

Feel free to open issues or submit pull requests if you have suggestions for improvements or new features!

---
*Created for the Project Zomboid Community.* ❤️
