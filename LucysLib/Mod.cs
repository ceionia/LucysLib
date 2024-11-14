using GDWeave;
using GDWeave.Godot;
using GDWeave.Godot.Variants;
using GDWeave.Modding;

namespace LucysLib;

public class Mod : IMod {
    public static IModInterface ModInterface;

    public Mod(IModInterface modInterface) {
        modInterface.Logger.Information("Lucy was here :3");
        ModInterface = modInterface;
        modInterface.RegisterScriptMod(new LucysNetFixes());
    }

    public void Dispose(){}
}

public record CodeChange {
    public required String name;
    public required Func<Token, bool>[] multitoken_prefix;
    public required Token[] code_to_add;
}

public class LucysNetFixes : IScriptMod {
    bool IScriptMod.ShouldRun(string path) => path == "res://Scenes/Singletons/SteamNetwork.gdc";

    CodeChange[] changes = {
        new CodeChange {
            name = "read packet intercept",
            // FLUSH_PACKET_INFORMATION[PACKET_SENDER] += 1
            // END
            multitoken_prefix = new Func<Token, bool>[] {
                t => t is IdentifierToken {Name: "FLUSH_PACKET_INFORMATION"},
                t => t.Type == TokenType.BracketOpen,
                t => t is IdentifierToken {Name: "PACKET_SENDER"},
                t => t.Type == TokenType.BracketClose,
                t => t.Type == TokenType.OpAssignAdd,
                t => t is ConstantToken {Value:IntVariant{Value: 1}},
                t => t.Type == TokenType.Newline,
            },
            // if $"/root/LucysLib".NetManager.process_packet(DATA, PACKET_SENDER, from_host): return
            // END
            code_to_add = new Token[] {
                new Token(TokenType.CfIf),
                new Token(TokenType.Dollar),
                new ConstantToken(new StringVariant("/root/LucysLib")),
                new Token(TokenType.Period),
                new IdentifierToken("NetManager"),
                new Token(TokenType.Period),
                new IdentifierToken("process_packet"),
                new Token(TokenType.ParenthesisOpen),
                new IdentifierToken("DATA"),
                new Token(TokenType.Comma),
                new IdentifierToken("PACKET_SENDER"),
                new Token(TokenType.Comma),
                new IdentifierToken("from_host"),
                new Token(TokenType.ParenthesisClose),
                new Token(TokenType.Colon),
                new Token(TokenType.CfReturn),
                new Token(TokenType.Newline, 2),
            }
        },
    };

    IEnumerable<Token> IScriptMod.Modify(string path, IEnumerable<Token> tokens)
    {
        var pending_changes = changes
            .Select(c => (c, new MultiTokenWaiter(c.multitoken_prefix)))
            .ToList();

        // I'm sure there's a better way to do this
        // with list comprehension stuff, but my 
        // C# is too rusty
        foreach (var token in tokens) {
            var had_change = false;
            foreach (var (change, waiter) in pending_changes) {
                if (waiter.Check(token)) {
                    Mod.ModInterface.Logger.Information($"Adding LucysLib Network mod {change.name}");

                    yield return token;
                    foreach (var t in change.code_to_add) yield return t;

                    had_change = true;
                    break;
                }
            }
            if (!had_change) yield return token;
        }
    }
}
