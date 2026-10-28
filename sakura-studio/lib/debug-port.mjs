import net from 'node:net';
export function validDebugPort(value){return Number.isInteger(value)&&value>=1024&&value<=65535;}
// Reserve an ephemeral loopback port, then release it immediately before the verified launcher.
// Any intervening owner is still rejected by the native process/profile ownership check.
export function freeDebugPort(){return new Promise((resolve,reject)=>{const probe=net.createServer();probe.once('error',reject);probe.listen(0,'127.0.0.1',()=>{const port=probe.address().port;probe.close(error=>error?reject(error):resolve(port));});});}
