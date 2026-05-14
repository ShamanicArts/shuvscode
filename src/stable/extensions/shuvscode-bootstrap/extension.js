const vscode = require('vscode');

const FLAG = 'shuvscode.bootstrapped';

// Bootstrap installs only third-party extensions we can't bake in.
// The default theme ships as the built-in `shuvscode-ember` extension.
const EXTENSIONS = [
  'vscode-icons-team.vscode-icons'
];

async function activate(ctx) {
  const enabled = vscode.workspace
    .getConfiguration('shuvscode.bootstrap')
    .get('enabled', true);

  if (!enabled || ctx.globalState.get(FLAG)) {
    return;
  }

  const results = await Promise.allSettled(
    EXTENSIONS
      .filter(id => !vscode.extensions.getExtension(id))
      .map(id =>
        vscode.commands.executeCommand(
          'workbench.extensions.installExtension',
          id
        )
      )
  );

  const anyFailure = results.some(r => r.status === 'rejected');

  if (!anyFailure) {
    await ctx.globalState.update(FLAG, true);
  }
}

function deactivate() {}

module.exports = {
  activate,
  deactivate
};
