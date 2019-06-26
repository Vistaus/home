namespace Philips.Hue {
    public class BridgeController {
        private Bridge _bridge;
        private Gee.HashMap<string, Models.Device> thing_map;

        public signal void on_new_lamp (Models.Lamp lamp);
        public signal void on_updated_lamp (Models.Lamp lamp);

        public BridgeController (Bridge bridge) {
            _bridge = bridge;
            thing_map = new Gee.HashMap<string, Models.Device> ();
        }

        public void get_description () {
            string url = "%sdescription.xml".printf (_bridge.base_url);

            var session = new Soup.Session ();
            var message = new Soup.Message ("GET", url);

            session.send_message (message);

            // replace <root xmlns="urn:schemas-upnp-org:device-1-0"> with <root>
            // because  otherwise the node can not be found
            GLib.Regex r = /.*(<root.*>).*/;
            Xml.Doc* doc;
            try {
                var patched = r.replace ((string) message.response_body.data, (ssize_t) message.response_body.length, 0, "<root>");

                Xml.Parser.init ();

                doc = Xml.Parser.parse_memory (patched, patched.length);
                if (doc == null) {
                    stderr.printf ("failed to read the .xml file\n");
                }

                Xml.XPath.Context context = new Xml.XPath.Context(doc);
                if (context == null) {
                    stderr.printf ("failed to create the xpath context\n");
                }

                Xml.XPath.Object* obj = context.eval_expression("/root/device/friendlyName");
                if (obj == null) {
                    stderr.printf ("failed to evaluate xpath\n");
                }

                Xml.Node* node = null;
                if (obj->nodesetval != null && obj->nodesetval->item(0) != null) {
                    node = obj->nodesetval->item(0);
                } else {
                    stderr.printf ("failed to find the expected node\n");
                }

                _bridge.name = node->get_content ();

                delete obj;

                obj = context.eval_expression("/root/device/manufacturer");
                if (obj == null) {
                    stderr.printf ("failed to evaluate xpath\n");
                }

                node = null;
                if (obj->nodesetval != null && obj->nodesetval->item(0) != null) {
                    node = obj->nodesetval->item(0);
                } else {
                    stderr.printf ("failed to find the expected node\n");
                }

                _bridge.manufacturer = node->get_content ();

                delete obj;

                obj = context.eval_expression("/root/device/modelName");
                if (obj == null) {
                    stderr.printf ("failed to evaluate xpath\n");
                }

                node = null;
                if (obj->nodesetval != null && obj->nodesetval->item(0) != null) {
                    node = obj->nodesetval->item(0);
                } else {
                    stderr.printf ("failed to find the expected node\n");
                }

                _bridge.model = node->get_content ();

                delete obj;
            } catch (GLib.RegexError e) {
                stderr.printf (e.message);
            } finally {
                delete doc;
            }

            Xml.Parser.cleanup ();
        }

        public bool register () throws GLib.Error {
            string url = "%sapi".printf (_bridge.base_url);

            var session = new Soup.Session ();
            var message = new Soup.Message ("POST", url);

            var gen = new Json.Generator ();
            var root = new Json.Node (Json.NodeType.OBJECT);
            var object = new Json.Object ();

            object.set_string_member ("devicetype", "com.github.manexim.home");

            root.set_object (object);
            gen.set_root (root);

            size_t length;
            string json = gen.to_data (out length);

            message.request_body.append_take (json.data);

            session.send_message (message);

            string response = (string) message.response_body.flatten ().data;

            var parser = new Json.Parser();
            parser.load_from_data (response, -1);

            foreach (var element in parser.get_root ().get_array ().get_elements ()) {
                var obj = element.get_object ();

                if (obj.has_member ("error")) {
                    throw new GLib.Error (
                        GLib.Quark.from_string (""),
                        (int) obj.get_object_member ("error").get_int_member ("type"),
                        obj.get_object_member ("error").get_string_member ("description")
                    );
                } else if (obj.has_member ("success")) {
                    _bridge.username = "%s".printf (obj.get_object_member ("success").get_string_member ("username"));
                    _bridge.power = Power.ON;

                    return true;
                }
            }

            return false;
        }

        public void state () {
            string url = "%sapi/%s".printf (_bridge.base_url, _bridge.username);

            var session = new Soup.Session ();
            var message = new Soup.Message ("GET", url);

            session.send_message (message);

            string response = (string) message.response_body.flatten ().data;

            try {
                var parser = new Json.Parser();
                parser.load_from_data (response, -1);
                var object = parser.get_root ().get_object ();
                var lights = object.get_object_member ("lights");

                foreach (var key in lights.get_members ()) {
                    var light = lights.get_object_member (key);
                    var lamp = new Philips.Hue.Lamp ();
                    lamp.name = light.get_string_member ("name");
                    lamp.manufacturer = light.get_string_member ("manufacturername");
                    lamp.model = light.get_string_member ("modelid");
                    lamp.id = light.get_string_member ("uniqueid");
                    var on = light.get_object_member ("state").get_boolean_member ("on");

                    if (on) {
                        lamp.power = Power.ON;
                    } else {
                        lamp.power = Power.OFF;
                    }

                    if (!thing_map.has_key (lamp.id)) {
                        thing_map.set (lamp.id, lamp);
                        on_new_lamp (lamp);
                    } else {
                        thing_map.set (lamp.id, lamp);
                        on_updated_lamp (lamp);
                    }
                }
            } catch (GLib.Error e) {
                stderr.printf (e.message);
            }
        }

        public Bridge bridge {
            get {
                return _bridge;
            }
        }
    }
}
