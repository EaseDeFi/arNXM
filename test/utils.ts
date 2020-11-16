export function hexSized(str: string, length: number) : string {
  const raw = Buffer.from(str).toString('hex');
  const pad = "0".repeat(length*2 - raw.length);
  return '0x' + raw + pad;
}
export function hex(str: string) : string {
  return '0x' + Buffer.from(str).toString('hex');
}
export function sleep(ms: number) {
  new Promise(resolve => setTimeout(resolve, ms));
}
