// Fixed development-only nonce: static server components cannot read a request
// nonce without opting the production tree back into dynamic rendering.
export const DEVELOPMENT_CSP_NONCE = "yen-development-csp-nonce";
