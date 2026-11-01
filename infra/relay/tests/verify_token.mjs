// Reads {token, pubkeys, now} from stdin, prints the Worker's verdict as JSON.
import { checkToken } from "../worker/src/index.js";

let raw = "";
for await (const chunk of process.stdin) raw += chunk;
const { offered, pubkeys, now } = JSON.parse(raw);
console.log(JSON.stringify(await checkToken(offered, pubkeys, now)));
