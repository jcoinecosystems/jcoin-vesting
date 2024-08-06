#!/usr/bin/env node

const ganache = require("ganache");



const mnemonic = "peanut stove atom casual fury recall caution bounce oven rely amused gain";



/*
[
  "0x56701933e3930cf7f3aeeedfdd0923acc0d5172b",  // owner
  "0x1a6ab725502a143bc05ce8915b0d50ea74478834",  // buyer
  "0x0ceb183b437f939403aac4abcb883b50033667be",  // signer
  "0xd5dca4a805634cc9b2f43a3d3d89aeeb9fecd0a2",
  "0x56f4698d10af8ab946738849c89e6e79978e11b6",
  "0xbcd21b2d95d0bfb34d6a54d40e0923a6e55091a0",
  "0x029eb6d10f83b2a625c60ccf39e231d4d2394a15",
  "0x44d3b37c6ba3dbe79702fb42aa53c5c85d98b7c4",
  "0x3c4f75b7f5f5c90699684c0a6e78559c1b7ab3d5",
  "0x88702af832a265ef3a07aff7bf14bab4f629acaf"
]
*/

const options = {
  mnemonic,
};
const server = ganache.server(options);


const PORT = 9545; // 0 means any available port
server.listen(PORT, async err => {
  if (err) throw err;

  console.log(`ganache listening on port ${server.address().port}...`);
  const provider = server.provider;
  const accounts = await provider.request({
    method: "eth_accounts",
    params: [],
  });
  //console.log(`ganache accounts: \n${JSON.stringify(accounts, null, 2)}`);
});
