-- list of different identifier we can sent to roslyn for diagnostic
local M = {
	WorkspaceDocumentsAndProject = "WorkspaceDocumentsAndProject",
	NonLocal = "NonLocal",
	Enc = "enc",
	DocumentAnalyzerSyntax = "DocumentAnalyzerSyntax",
	HotReloadDiagnostics = "HotReloadDiagnostics",
	XamlDiagnostics = "XamlDiagnostics",
	DocumentCompilerSemantic = "DocumentCompilerSemantic",
	Syntax = "syntax",
}

return M
