/// Every fixed-location rule. Project build folders live in `ProjectRules`.
public enum Catalog {
    public static var all: [Rule] { AppleRules.all + ToolchainRules.all + AIRules.all }
}
