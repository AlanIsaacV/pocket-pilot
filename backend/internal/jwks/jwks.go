package jwks

import (
	"crypto/rsa"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"math/big"
	"net/http"
	"sync"
	"time"
)

const cacheTTL = 1 * time.Hour

var providerJWKSURLs = map[string]string{
	"google": "https://www.googleapis.com/oauth2/v3/certs",
	"apple":  "https://appleid.apple.com/auth/keys",
}

type jwkSet struct {
	Keys []jwk `json:"keys"`
}

type jwk struct {
	Kid string `json:"kid"`
	Kty string `json:"kty"`
	Alg string `json:"alg"`
	N   string `json:"n"`
	E   string `json:"e"`
}

type cachedKeys struct {
	keys      map[string]*rsa.PublicKey
	fetchedAt time.Time
}

type KeyStore struct {
	mu    sync.RWMutex
	cache map[string]*cachedKeys
}

func NewKeyStore() *KeyStore {
	return &KeyStore{
		cache: make(map[string]*cachedKeys),
	}
}

func (ks *KeyStore) GetKey(provider, kid string) (*rsa.PublicKey, error) {
	jwksURL, ok := providerJWKSURLs[provider]
	if !ok {
		return nil, fmt.Errorf("unknown provider: %s", provider)
	}

	ks.mu.RLock()
	cached, ok := ks.cache[provider]
	ks.mu.RUnlock()

	if ok && time.Since(cached.fetchedAt) < cacheTTL {
		if key, found := cached.keys[kid]; found {
			return key, nil
		}
	}

	keys, err := fetchJWKS(jwksURL)
	if err != nil {
		return nil, fmt.Errorf("fetch JWKS for %s: %w", provider, err)
	}

	ks.mu.Lock()
	ks.cache[provider] = &cachedKeys{keys: keys, fetchedAt: time.Now()}
	ks.mu.Unlock()

	key, found := keys[kid]
	if !found {
		return nil, fmt.Errorf("kid %q not found in %s JWKS", kid, provider)
	}
	return key, nil
}

func fetchJWKS(url string) (map[string]*rsa.PublicKey, error) {
	resp, err := http.Get(url)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("JWKS endpoint returned %d", resp.StatusCode)
	}

	var set jwkSet
	if err := json.NewDecoder(resp.Body).Decode(&set); err != nil {
		return nil, fmt.Errorf("decode JWKS: %w", err)
	}

	keys := make(map[string]*rsa.PublicKey, len(set.Keys))
	for _, k := range set.Keys {
		if k.Kty != "RSA" {
			continue
		}
		pub, err := parseRSAPublicKey(k.N, k.E)
		if err != nil {
			return nil, fmt.Errorf("parse key kid=%s: %w", k.Kid, err)
		}
		keys[k.Kid] = pub
	}
	return keys, nil
}

func parseRSAPublicKey(nB64, eB64 string) (*rsa.PublicKey, error) {
	nBytes, err := base64.RawURLEncoding.DecodeString(nB64)
	if err != nil {
		return nil, fmt.Errorf("decode n: %w", err)
	}

	eBytes, err := base64.RawURLEncoding.DecodeString(eB64)
	if err != nil {
		return nil, fmt.Errorf("decode e: %w", err)
	}

	n := new(big.Int).SetBytes(nBytes)
	e := 0
	for _, b := range eBytes {
		e = e<<8 + int(b)
	}

	return &rsa.PublicKey{N: n, E: e}, nil
}
