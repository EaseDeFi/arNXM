export function hex(str: string) : string {
  return '0x' + Buffer.from(str).toString('hex');
}
export function sleep(ms: number) {
  new Promise(resolve => setTimeout(resolve, ms));
}
