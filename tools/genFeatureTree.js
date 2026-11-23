const fs = require("node:fs/promises");
const path = require("node:path");
const { execFile } = require("node:child_process");
const { promisify } = require("node:util");

const execFileAsync = promisify(execFile);

const ROOT_PATH = path.resolve(__dirname, "..");
const BASE_PATH = path.join(ROOT_PATH, "src");
const PROJECT_PATH = path.join(ROOT_PATH, "default.project.json");
const SOURCEMAP_PATH = path.join(ROOT_PATH, "sourcemap.json");

const BLACKLISTED_DIRS = new Set([path.resolve(BASE_PATH, "startup")]);
const NON_SERVER_NAMES = new Set(["servertime"]);
const PROJECT_NAME = "genfeaturetree";

function toPascalCase(value) {
  if (value.toLowerCase() === "ui") return "UI";
  return value.charAt(0).toUpperCase() + value.slice(1);
}

function toPosix(value) {
  return value.split(path.sep).join("/");
}

function isWithin(parent, child) {
  const relative = path.relative(parent, child);
  return (
    relative === "" ||
    (!relative.startsWith(`..${path.sep}`) &&
    relative !== ".." &&
    !path.isAbsolute(relative))
  );
}

function getRelativePath(filepath) {
  return toPosix(path.relative(ROOT_PATH, filepath));
}

function getScriptInfo(filepath) {
  const relative = path.relative(BASE_PATH, filepath);
  const parts = relative.split(path.sep);
  const filename = path.basename(filepath, ".luau");
  const lowerName = filename.toLowerCase();

  const isInit = lowerName === "init" || lowerName.startsWith("init.");
  const isServer = lowerName.includes("server") &&
  ![...NON_SERVER_NAMES].some((name) => lowerName.includes(name));

  const folderName = parts.length > 1
    ? toPascalCase(parts[parts.length - 2])
    : "";

  let name = filename;
  let runContext;

  if (isInit) {
    name = folderName || PROJECT_NAME;
    if (lowerName.endsWith(".server")) {
      runContext = "Server";
    } else if (lowerName.endsWith(".client")) {
      runContext = "Client";
    }
  } else if (
    ["server", "client", "utils", "types"].includes(lowerName)
  ) {
    name = folderName + toPascalCase(filename);
  }

  const folder = parts.slice(0, -1).map(toPascalCase);

  return {
    filepath,
    relative,
    filename,
    lowerName,
    isInit,
    isServer,
    runContext,
    target: isServer ? "ServerScriptService" : "ReplicatedStorage",
    folder,
    name,
    file: getRelativePath(
      isInit ? path.dirname(filepath) : filepath
    ),
    directory: path.dirname(filepath),
  };
}

async function walkLuauFiles(directory) {
  const results = [];
  const pending = [directory];

  while (pending.length > 0) {
    const current = pending.pop();

    if (BLACKLISTED_DIRS.has(path.resolve(current))) {
      continue;
    }

    const entries = await fs.readdir(current, {
      withFileTypes: true,
    });

    entries.sort((a, b) => a.name.localeCompare(b.name));

    for (const entry of entries) {
      const filepath = path.join(current, entry.name);

      if (entry.isDirectory()) {
        pending.push(filepath);
      } else if (
        entry.isFile() &&
        entry.name.endsWith(".luau")
      ) {
        results.push(getScriptInfo(filepath));
      }
    }
  }

  results.sort((a, b) =>
    toPosix(a.relative).localeCompare(toPosix(b.relative))
  );

  return results;
}

function createTree() {
  return {
    emitLegacyScripts: false,
    name: PROJECT_NAME,
    tree: {
      $className: "DataModel",

      ReplicatedStorage: {
        Source: {
          $className: "Folder",
          Features: { $className: "Folder" },
          Core: { $className: "Folder" },
          Game: { $className: "Folder" },
          Client: { $path: "src/startup/Client.client.luau" },
        },
        Packages: { $path: "Packages" },
      },

      ServerScriptService: {
        Features: { $className: "Folder" },
        Server: { $path: "src/startup/Server.server.luau" },
        Packages: { $path: "ServerPackages" },
      },
    },
  };
}

function getOrCreateFolder(root, folderParts) {
  let current = root;

  for (const part of folderParts) {
    const key = part.toLowerCase();

    if (!current.__folderIndex) {
      Object.defineProperty(current, "__folderIndex", {
        value: new Map(),
        enumerable: false,
      });

      for (const existing of Object.keys(current)) {
        current.__folderIndex.set(existing.toLowerCase(), existing);
      }
    }

    let actualKey = current.__folderIndex.get(key);

    if (actualKey === undefined) {
      actualKey = part;
      current[actualKey] = { $className: "Folder" };
      current.__folderIndex.set(key, actualKey);
    }

    current = current[actualKey];
  }

  return current;
}

function makeEntry(info) {
  const entry = { $path: info.file };

  if (info.runContext) {
    entry.$properties = { RunContext: info.runContext };
  }

  return entry;
}

function getMountedInitDirectories(files) {
  const initDirectories = new Map();

  for (const info of files) {
    if (!info.isInit) continue;

    const key = [
      info.target,
      ...info.folder.map((part) => part.toLowerCase()),
    ].join("/");

    const previous = initDirectories.get(key);

    if (previous) {
      throw new Error(
        `Multiple init scripts mount the same folder:\n` +
        `  ${previous.relative}\n` +
        `  ${info.relative}`
      );
    }

    initDirectories.set(key, info);
  }

  return initDirectories;
}

function isInsideMountedDirectory(info, initDirectories) {
  let current = path.dirname(info.filepath);

  while (isWithin(BASE_PATH, current)) {
    const relative = path.relative(BASE_PATH, current);
    const parts = relative === ""
      ? []
      : relative.split(path.sep).map(toPascalCase);

    const key = [
      info.target,
      ...parts.map((part) => part.toLowerCase()),
    ].join("/");

    if (initDirectories.has(key)) {
      return true;
    }

    if (current === BASE_PATH) break;

    const parent = path.dirname(current);
    if (parent === current) break;
    current = parent;
  }

  return false;
}

function insertEntry(root, folder, name, entry, sourcePath) {
  const parent = getOrCreateFolder(root, folder);
  const existingKey = Object.keys(parent).find(
    (key) => key.toLowerCase() === name.toLowerCase()
  );

  if (existingKey !== undefined) {
    throw new Error(
      `Project-tree name collision: "${name}"\n` +
      `  at ${sourcePath}\n` +
      `  conflicts with "${existingKey}"`
    );
  }

  parent[name] = entry;
}

function buildProjectTree(files) {
  const project = createTree();
  const sharedRoot = project.tree.ReplicatedStorage.Source;
  const serverRoot = project.tree.ServerScriptService;
  const initDirectories = getMountedInitDirectories(files);

  for (const info of files) {
    if (!info.isInit) continue;

    const root = info.target === "ServerScriptService"
      ? serverRoot
      : sharedRoot;

    insertEntry(
      root,
      info.folder.slice(0, -1),
      info.name,
      makeEntry(info),
      info.relative
    );
  }

  for (const info of files) {
    if (info.isInit) continue;
    if (isInsideMountedDirectory(info, initDirectories)) continue;

    const root = info.target === "ServerScriptService"
      ? serverRoot
      : sharedRoot;

    insertEntry(
      root,
      info.folder,
      info.name,
      makeEntry(info),
      info.relative
    );
  }

  return project;
}

async function writeIfChanged(filepath, contents) {
  let previous;

  try {
    previous = await fs.readFile(filepath, "utf8");
  } catch (error) {
    if (error.code !== "ENOENT") throw error;
  }

  if (previous === contents) {
    return false;
  }

  await fs.mkdir(path.dirname(filepath), { recursive: true });

  const temporaryPath =
    `${filepath}.${process.pid}.${Date.now()}.tmp`;

  try {
    await fs.writeFile(temporaryPath, contents, "utf8");
    await fs.rename(temporaryPath, filepath);
  } catch (error) {
    await fs.rm(temporaryPath, { force: true }).catch(() => {});
    throw error;
  }

  return true;
}

async function generateSourcemap() {
  const rojoExecutable = process.env.ROJO_BIN || "rojo";

  try {
    await execFileAsync(
      rojoExecutable,
      [
        "sourcemap",
        "default.project.json",
        "--output",
        "sourcemap.json",
      ],
      {
        cwd: ROOT_PATH,
        windowsHide: true,
        maxBuffer: 16 * 1024 * 1024,
      }
    );
  } catch (error) {
    throw new Error(
      `Rojo sourcemap generation failed.\n` +
      `${error.stderr || error.message}`
    );
  }
}

async function main() {
  const startedAt = performance.now();
  const files = await walkLuauFiles(BASE_PATH);
  const project = buildProjectTree(files);
  const projectContents = JSON.stringify(project, null, 2) + "\n";
  const projectChanged = await writeIfChanged(
    PROJECT_PATH,
    projectContents
  );

  let sourcemapExists = true;

  try {
    await fs.access(SOURCEMAP_PATH);
  } catch (error) {
    if (error.code === "ENOENT") {
      sourcemapExists = false;
    } else {
      throw error;
    }
  }

  if (projectChanged || !sourcemapExists) {
    await generateSourcemap();
  }

  const elapsed = (performance.now() - startedAt).toFixed(1);

  console.log(
    `✅ Generated project tree in ${elapsed} ms\n` +
    `  Luau files scanned: ${files.length}\n` +
    `  default.project.json: ${projectChanged ? "updated" : "unchanged"}\n` +
    `  sourcemap.json: ${
      projectChanged || !sourcemapExists ? "regenerated" : "unchanged"
    }`
  );
}

main().catch((error) => {
  console.error("❌ Project generation failed:\n", error);
  process.exitCode = 1;
});
