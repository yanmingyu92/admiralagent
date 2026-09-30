import subprocess, os, json, pathlib, shutil
root = pathlib.Path(__file__).resolve().parent.parent.parent
audit = root / "audit" / "round3"
env = os.environ.copy()
for k in ["LC_ALL", "LC_CTYPE", "LANG"]: env[k] = "English_United States.utf8"
env["R_LIBS"] = str(audit / "check-delivery" / "admiralagent.Rcheck")
rscript = "C:/Users/JaimeYan/AppData/Local/Programs/R/R-4.6.0/bin/Rscript.exe"
standalone = audit / "mcp-standalone.R"
shutil.copyfile(root / "tools" / "mcp_server.R", standalone)
requests = [
 {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"audit","version":"1"}}},
 {"jsonrpc":"2.0","id":2,"method":"tools/list"},
 {"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"aa_validate_ir","arguments":{"ir":[{"dataset":"ADSL","variable":"X","steps":[{"layer":"compute_var","args":{"target":"X","formula":"AGE;1"}}],"confidence":1,"needs_human":False}]}}}
]
for mode, script in [("source",root / "tools" / "mcp_server.R"),("installed",standalone)]:
 out = subprocess.run([rscript,str(script)],input=("\n".join(json.dumps(x) for x in requests)+"\n").encode(),capture_output=True,env=env,cwd=audit,timeout=60)
 (audit / f"mcp-{mode}.jsonl").write_bytes(out.stdout)
 (audit / f"mcp-{mode}.stderr").write_bytes(out.stderr)
 replies = [json.loads(x) for x in out.stdout.splitlines()]
 assert out.returncode == 0 and len(replies) == 3, (mode,out.stderr)
 assert len(replies[1]["result"]["tools"]) == 5
 verdict = json.loads(replies[2]["result"]["content"][0]["text"])
 assert verdict["valid"] is False
 print(mode,"PASS; initialize / 5 tools / malicious IR rejected")
