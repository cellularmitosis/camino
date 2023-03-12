/* -*- Mode: C++; tab-width: 2; indent-tabs-mode: nil; c-basic-offset: 2 -*- */
/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

#import "NSString+Utils.h"
#import "NSString+Gecko.h"
#import "NSDate+Utils.h"

#import "nsCOMPtr.h"
#import "nsString.h"
#import "nsIMutableArray.h"

#import "nsIX509Cert.h"
#import "nsIX509CertValidity.h"
#import "nsIX509CertDB.h"

#import "nsIASN1Object.h"
#import "nsIASN1Sequence.h"

#import "nsIStringBundle.h"

#import "nsServiceManagerUtils.h"

#import "CertificateItem.h"

NSString* const kCertificateChangedNotification = @"CertificateChangedNotification";

@interface CertificateItem(Private)

- (NSString*)stringForDate:(NSDate*)inDate;

- (PRUint32)validityForUsage:(PRUint32)inUsage;
- (PRUint32)generalValidity;    // whether it's verified for at least one usage

- (NSString*)shortValidityKeyForVerifyState:(PRUint32)inVverifyState;
- (NSString*)longValidityKeyForVerifyState:(PRUint32)inVerifyState;

- (NSColor*)textColorForValidity;

- (NSDictionary*)traverseSequence:(nsIASN1Sequence*)inSequence;
- (void)ensureASN1Info;
- (NSString*)ASN1PropertyWithKeyPath:(NSArray*)inKeyPath;

- (void)postChangedNotification;
- (void)certificateChanged:(NSNotification*)inNotification;


@end

#pragma mark -

@implementation CertificateItem

+ (CertificateItem*)certificateItemWithCert:(nsIX509Cert*)inCert
{
  return [[[CertificateItem alloc] initWithCert:inCert] autorelease];
}

- (id)initWithCert:(nsIX509Cert*)inCert
{
  if ((self = [super init]))
  {
    mCert = inCert;
    NS_ADDREF(mCert);

    // we need to listen for changes in our parent chain, to update cached trust
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(certificateChanged:)
                                                 name:kCertificateChangedNotification
                                               object:nil];
  }
  return self;
}

- (void)dealloc
{
  [[NSNotificationCenter defaultCenter] removeObserver:self];
  [mASN1InfoDict release];
  NS_RELEASE(mCert);
  [mFallbackProblemMessageKey release];
  [super dealloc];
}

- (nsIX509Cert*)cert
{
  return mCert;
}

- (BOOL)isSameCertAs:(nsIX509Cert*)inCert
{
  if (!inCert)
    return NO;

  if (mCert == inCert)
    return YES;

  PRBool isSame;
  return (NS_SUCCEEDED(mCert->Equals(inCert, &isSame)) && isSame);
}

- (BOOL)isEqualTo:(id)object
{
  if (![object isKindOfClass:[self class]])
    return NO;

  return [self isSameCertAs:[object cert]];
}

- (BOOL)certificateIsIssuerCert:(CertificateItem*)inCert
{
  nsCOMPtr<nsIX509Cert> issuerCert;
  mCert->GetIssuer(getter_AddRefs(issuerCert));
  return [inCert isSameCertAs:issuerCert];
}

- (BOOL)certificateIsInParentChain:(CertificateItem*)inCert
{
  nsIX509Cert* testCert = [inCert cert];
  if (!testCert) return NO;

  nsCOMPtr<nsIArray> parentChain;
  if (NS_FAILED(mCert->GetChain(getter_AddRefs(parentChain))) || !parentChain)
    return NO;

  PRUint32 chainLength;
  if (NS_FAILED(parentChain->GetLength(&chainLength)))
    return NO;
    
  for (PRUint32 i = 0; i < chainLength; i ++)
  {
    nsCOMPtr<nsIX509Cert> thisCert;
    parentChain->QueryElementAt(i, NS_GET_IID(nsIX509Cert),
                                getter_AddRefs(thisCert));
    if (!thisCert) continue;
    
    PRBool isSameCert;
    if (NS_SUCCEEDED(thisCert->Equals(testCert, &isSameCert)) && isSameCert)
      return YES;
  }
  
  return NO;
}

- (NSString*)displayName
{
  // do what NSS does
  NSString* displayString = [self commonName];
  if ([displayString length] == 0)
  {
    NSString* nick = [self nickname];
    // only show stuff after the first colon
    NSRange colonRange = [nick rangeOfString:@":"];
    if (colonRange.location != NSNotFound)
      displayString = [[nick substringFromIndex:colonRange.location + 1] stringByTrimmingWhitespace];
    else
      displayString = nick;
  }
  return displayString;
}

- (NSString*)nickname
{
  nsAutoString tempString;
  mCert->GetNickname(tempString);
  return [NSString stringWith_nsAString:tempString];
}

- (NSString*)subjectName
{
  nsAutoString tempString;
  mCert->GetSubjectName(tempString);
  return [NSString stringWith_nsAString:tempString];
}

- (NSString*)organization
{
  nsAutoString tempString;
  mCert->GetOrganization(tempString);
  return [NSString stringWith_nsAString:tempString];
}

- (NSString*)organizationalUnit
{
  nsAutoString tempString;
  mCert->GetOrganizationalUnit(tempString);
  return [NSString stringWith_nsAString:tempString];
}

- (NSString*)commonName
{
  nsAutoString tempString;
  mCert->GetCommonName(tempString);
  return [NSString stringWith_nsAString:tempString];
}

- (NSString*)emailAddress
{
  nsAutoString tempString;
  mCert->GetEmailAddress(tempString);
  return [NSString stringWith_nsAString:tempString];
}

- (NSString*)serialNumber
{
  nsAutoString tempString;
  mCert->GetSerialNumber(tempString);
  return [NSString stringWith_nsAString:tempString];
}

- (NSString*)sha1Fingerprint
{
  nsAutoString tempString;
  mCert->GetSha1Fingerprint(tempString);
  return [NSString stringWith_nsAString:tempString];
}

- (NSString*)md5Fingerprint
{
  nsAutoString tempString;
  mCert->GetMd5Fingerprint(tempString);
  return [NSString stringWith_nsAString:tempString];
}

- (NSString*)issuerName
{
  nsAutoString tempString;
  mCert->GetIssuerName(tempString);
  return [NSString stringWith_nsAString:tempString];
}

- (NSString*)issuerCommonName
{
  nsAutoString tempString;
  mCert->GetIssuerCommonName(tempString);
  return [NSString stringWith_nsAString:tempString];
}

- (NSString*)issuerOrganization
{
  nsAutoString tempString;
  mCert->GetIssuerOrganization(tempString);
  return [NSString stringWith_nsAString:tempString];
}

- (NSString*)issuerOrganizationalUnit
{
  nsAutoString tempString;
  mCert->GetIssuerOrganizationUnit(tempString);
  return [NSString stringWith_nsAString:tempString];
}

- (NSString*)signatureAlgorithm
{
  return [self ASN1PropertyWithKeyPath:[NSArray arrayWithObjects:@"CertDumpSigAlg", nil]];
}

- (NSString*)signatureValue
{
  return [self ASN1PropertyWithKeyPath:[NSArray arrayWithObjects:@"CertDumpCertSig", nil]];
}

- (NSString*)publicKeyAlgorithm
{
  return [self ASN1PropertyWithKeyPath:[NSArray arrayWithObjects:@"CertDumpCertificate", @"CertDumpSPKI", @"CertDumpSPKIAlg", nil]];
}

- (NSString*)publicKey
{
  return [self ASN1PropertyWithKeyPath:[NSArray arrayWithObjects:@"CertDumpCertificate", @"CertDumpSPKI", @"CertDumpSubjPubKey", nil]];
}

- (NSString*)publicKeySizeBits
{
  NSString* theKey = [[self publicKey] stringByRemovingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  // afaict, no better way to get this. stupid!
  // XXX this returns the wrong value right now. -publicKey returns a DER encoded key, which we'd
  // have to decode to get the modulus (which is the part we care about)
  unsigned int stringLength = [theKey length];
  // two chars per byte, 8 bits per byte
  unsigned int numBits = (stringLength / 2) * 8;
  return [NSString stringWithFormat:@"%u", numBits];
}

- (NSString*)version   // certificate "Version"
{
  return [self ASN1PropertyWithKeyPath:[NSArray arrayWithObjects:@"CertDumpCertificate", @"CertDumpVersion", nil]];
}

- (NSString*)usagesStringIgnoringOSCP:(BOOL)inIgnoreOSCP
{
  nsAutoString tempString;
  PRUint32 verified = 0;
  mCert->GetUsagesString(inIgnoreOSCP, &verified, tempString);
  return [NSString stringWith_nsAString:tempString];
}

- (NSArray*)validUsages
{
  NSMutableArray* usages = [NSMutableArray array];
  
  // like mCert->GetUsagesArray(), but with better strings
  PRUint32 curVerify;
  if (NS_SUCCEEDED(mCert->VerifyForUsage(nsIX509Cert::CERT_USAGE_SSLClient, &curVerify)) && curVerify == nsIX509Cert::VERIFIED_OK)
    [usages addObject:NSLocalizedStringFromTable(@"VerifySSLClient", @"CertificateDialogs", @"")];

  if (NS_SUCCEEDED(mCert->VerifyForUsage(nsIX509Cert::CERT_USAGE_SSLServer, &curVerify)) && curVerify == nsIX509Cert::VERIFIED_OK)
    [usages addObject:NSLocalizedStringFromTable(@"VerifySSLServer", @"CertificateDialogs", @"")];

  if (NS_SUCCEEDED(mCert->VerifyForUsage(nsIX509Cert::CERT_USAGE_SSLServerWithStepUp, &curVerify)) && curVerify == nsIX509Cert::VERIFIED_OK)
    [usages addObject:NSLocalizedStringFromTable(@"VerifySSLStepUp", @"CertificateDialogs", @"")];

  if (NS_SUCCEEDED(mCert->VerifyForUsage(nsIX509Cert::CERT_USAGE_EmailSigner, &curVerify)) && curVerify == nsIX509Cert::VERIFIED_OK)
    [usages addObject:NSLocalizedStringFromTable(@"VerifyEmailSigner", @"CertificateDialogs", @"")];

  if (NS_SUCCEEDED(mCert->VerifyForUsage(nsIX509Cert::CERT_USAGE_EmailRecipient, &curVerify)) && curVerify == nsIX509Cert::VERIFIED_OK)
    [usages addObject:NSLocalizedStringFromTable(@"VerifyEmailRecip", @"CertificateDialogs", @"")];

  if (NS_SUCCEEDED(mCert->VerifyForUsage(nsIX509Cert::CERT_USAGE_ObjectSigner, &curVerify)) && curVerify == nsIX509Cert::VERIFIED_OK)
    [usages addObject:NSLocalizedStringFromTable(@"VerifyObjSign", @"CertificateDialogs", @"")];

  if (NS_SUCCEEDED(mCert->VerifyForUsage(nsIX509Cert::CERT_USAGE_SSLCA, &curVerify)) && curVerify == nsIX509Cert::VERIFIED_OK)
    [usages addObject:NSLocalizedStringFromTable(@"VerifySSLCA", @"CertificateDialogs", @"")];

  if (NS_SUCCEEDED(mCert->VerifyForUsage(nsIX509Cert::CERT_USAGE_StatusResponder, &curVerify)) && curVerify == nsIX509Cert::VERIFIED_OK)
    [usages addObject:NSLocalizedStringFromTable(@"VerifyStatusResponder", @"CertificateDialogs", @"")];

/*
  // nsUsageArrayHelper::GetUsagesArray doesn't return any of these, so we won't either

  if (NS_SUCCEEDED(mCert->VerifyForUsage(nsIX509Cert::CERT_USAGE_UserCertImport, &curVerify)) && curVerify == nsIX509Cert::VERIFIED_OK)
    [usages addObject:NSLocalizedStringFromTable(@"VerifyUserImport", @"CertificateDialogs", @"")];

  if (NS_SUCCEEDED(mCert->VerifyForUsage(nsIX509Cert::CERT_USAGE_VerifyCA, &curVerify)) && curVerify == nsIX509Cert::VERIFIED_OK)
    [usages addObject:NSLocalizedStringFromTable(@"VerifyCAVerifier", @"CertificateDialogs", @"")];

  if (NS_SUCCEEDED(mCert->VerifyForUsage(nsIX509Cert::CERT_USAGE_ProtectedObjectSigner, &curVerify)) && curVerify == nsIX509Cert::VERIFIED_OK)
    [usages addObject:NSLocalizedStringFromTable(@"VerifyProtectObjSign", @"CertificateDialogs", @"")];

  if (NS_SUCCEEDED(mCert->VerifyForUsage(nsIX509Cert::CERT_USAGE_AnyCA, &curVerify)) && curVerify == nsIX509Cert::VERIFIED_OK)
    [usages addObject:NSLocalizedStringFromTable(@"VerifyAnyCA", @"CertificateDialogs", @"")];
*/  
  return usages;
}

- (BOOL)isRootCACert
{
  nsCOMPtr<nsIX509Cert> issuerCert;
  mCert->GetIssuer(getter_AddRefs(issuerCert));
  return (issuerCert && [self isSameCertAs:issuerCert]);
}

- (BOOL)isUntrustedRootCACert
{
  return [self isRootCACert] && ([self generalValidity] == nsIX509Cert::ISSUER_NOT_TRUSTED);
}

- (NSDate*)expiresDate
{
  nsCOMPtr<nsIX509CertValidity> certValidity;
  if (NS_SUCCEEDED(mCert->GetValidity(getter_AddRefs(certValidity))))
  {
    PRTime expireTime;
    if (NS_SUCCEEDED(certValidity->GetNotAfter(&expireTime)))
      return [NSDate dateWithPRTime:expireTime];
  }
  return nil;
}

- (NSString*)expiresString
{
  return [self stringForDate:[self expiresDate]];
}

- (NSDate*)validFromDate
{
  nsCOMPtr<nsIX509CertValidity> certValidity;
  if (NS_SUCCEEDED(mCert->GetValidity(getter_AddRefs(certValidity))))
  {
    PRTime startTime;
    if (NS_SUCCEEDED(certValidity->GetNotBefore(&startTime)))
      return [NSDate dateWithPRTime:startTime];
  }
  return nil;
}

- (NSString*)validFromString
{
  return [self stringForDate:[self validFromDate]];
}

- (BOOL)isExpired
{
  return ([[self expiresDate] compare:[NSDate date]] == NSOrderedAscending);
}

- (BOOL)isNotYetValid
{
  return ([[self validFromDate] compare:[NSDate date]] == NSOrderedDescending);
}

- (BOOL)isValid
{
  return ([self generalValidity] == nsIX509Cert::VERIFIED_OK) &&
         !mDomainIsMismatched;
}

- (NSString*)validity
{
  NSString* stateKey    = [self shortValidityKeyForVerifyState:[self generalValidity]];
  return NSLocalizedStringFromTable(stateKey, @"CertificateDialogs", @"");
}

- (NSColor*)textColorForValidity
{
  if ([self isUntrustedRootCACert])
    return [NSColor orangeColor];

  if (![self isValid] || mDomainIsMismatched)
    return [NSColor redColor];

  return [NSColor blackColor];
}

- (NSAttributedString*)attributedShortValidityString
{
  NSString* stateKey    = [self shortValidityKeyForVerifyState:[self generalValidity]];
    
  NSDictionary* attribs = [NSDictionary dictionaryWithObject:[self textColorForValidity] forKey:NSForegroundColorAttributeName];
  return [[[NSAttributedString alloc] initWithString:NSLocalizedStringFromTable(stateKey, @"CertificateDialogs", @"")
                                          attributes:attribs] autorelease];
}

- (NSAttributedString*)attributedLongValidityString
{
  NSString* stateKey    = [self longValidityKeyForVerifyState:[self generalValidity]];

  NSDictionary* attribs = [NSDictionary dictionaryWithObject:[self textColorForValidity] forKey:NSForegroundColorAttributeName];
  return [[[NSAttributedString alloc] initWithString:NSLocalizedStringFromTable(stateKey, @"CertificateDialogs", @"")
                                          attributes:attribs] autorelease];
}

// key-value coding compliance
- (id)valueForUndefinedKey:(NSString*)inKey
{
  return nil;
}

- (NSString*)stringForDate:(NSDate*)inDate
{
  if (!inDate) {
    return @"";
  }

  NSDateFormatter* dateFormatter = [[NSDateFormatter alloc] init];
  [dateFormatter setFormatterBehavior:NSDateFormatterBehavior10_4];
  [dateFormatter setDateStyle:NSDateFormatterLongStyle];
  [dateFormatter setTimeStyle:NSDateFormatterLongStyle];
  NSString* string = [dateFormatter stringFromDate:inDate];
  [dateFormatter release];
  return string;
}

- (PRUint32)validityForUsage:(PRUint32)inUsage
{
  PRUint32 verifyState;
  nsresult rv = mCert->VerifyForUsage(inUsage, &verifyState);
  if (NS_FAILED(rv))
    verifyState = nsIX509Cert::NOT_VERIFIED_UNKNOWN;

  return verifyState;
}

- (PRUint32)generalValidity
{
  if (mGotVerification)
    return mVerification;

  PRUint32 verified;

  // testing
  nsAutoString usages;
  PRBool ignoreOcsp = PR_TRUE;
  if (NS_FAILED(mCert->GetUsagesString(ignoreOcsp, &verified, usages)))
    verified = nsIX509Cert::NOT_VERIFIED_UNKNOWN;

#if 0
  NSLog(@"GetUsagesString returned %d (%@)", verified, [NSString stringWith_nsAString:usages]);

  PRUint32 testVerified;
  mCert->VerifyForUsage(nsIX509Cert::CERT_USAGE_SSLClient, &testVerified);
  NSLog(@"%@ GetUsagesString verified for SSL client: %d", self, testVerified);

  mCert->VerifyForUsage(nsIX509Cert::CERT_USAGE_SSLServer, &testVerified);
  NSLog(@"%@ GetUsagesString verified for SSL server: %d", self, testVerified);

  mCert->VerifyForUsage(nsIX509Cert::CERT_USAGE_SSLCA, &testVerified);
  NSLog(@"%@ GetUsagesString verified for SSL CA; %d", self, testVerified);

  mCert->VerifyForUsage(nsIX509Cert::CERT_USAGE_EmailSigner, &testVerified);
  NSLog(@"%@ GetUsagesString verified for email signer; %d", self, testVerified);

  mCert->VerifyForUsage(nsIX509Cert::CERT_USAGE_EmailRecipient, &testVerified);
  NSLog(@"%@ GetUsagesString verified for email recipient; %d", self, testVerified);

  mCert->VerifyForUsage(nsIX509Cert::CERT_USAGE_ObjectSigner, &testVerified);
  NSLog(@"%@ GetUsagesString verified for object signing; %d", self, testVerified);

  mCert->VerifyForUsage(nsIX509Cert::CERT_USAGE_VerifyCA, &testVerified);
  NSLog(@"%@ GetUsagesString verified for verify CA; %d", self, testVerified);
#endif

  mVerification = verified;
  mGotVerification = YES;
  return verified;
}

- (NSString*)shortValidityKeyForVerifyState:(PRUint32)inVerifyState
{
  NSString* longStateKey = [self longValidityKeyForVerifyState:inVerifyState];
  return [NSString stringWithFormat:@"Short%@", longStateKey];
}

- (NSString*)longValidityKeyForVerifyState:(PRUint32)inVerifyState
{
  NSString* stateKey = @"";
  switch (inVerifyState)
  {
    case nsIX509Cert::VERIFIED_OK:
      if (mDomainIsMismatched)
        stateKey = @"InvalidStateMismatchedDomain";
      else
        stateKey = @"ValidStateOK";
      break;
    default:
    case nsIX509Cert::USAGE_NOT_ALLOWED:
    case nsIX509Cert::NOT_VERIFIED_UNKNOWN:
      if (mFallbackProblemMessageKey)
        stateKey = mFallbackProblemMessageKey;
      else
        stateKey = @"InvalidStateVerifyFailed";
      break;
    case nsIX509Cert::CERT_REVOKED:         stateKey = @"InvalidStateRevoked";            break;
    case nsIX509Cert::CERT_NOT_TRUSTED:     stateKey = @"InvalidStateCertNotTrusted";     break;
    case nsIX509Cert::ISSUER_NOT_TRUSTED:
      // if the issuer is us
      if ([self isRootCACert])
        stateKey = @"InvalidStateIsUntrustedRootCert";
      else
        stateKey = @"InvalidStateIssuerNotTrusted";
      break;

    case nsIX509Cert::ISSUER_UNKNOWN:       stateKey = @"InvalidStateIssuerNotKnown";     break;
    case nsIX509Cert::INVALID_CA:           stateKey = @"InvalidStateInvalidIssuerCert";  break;
    case nsIX509Cert::CERT_EXPIRED:
      if ([self isNotYetValid])
        stateKey = @"InvalidStateNotYetValid";
      else
        stateKey = @"InvalidStateExpired";
      break;
  }
  return stateKey;
}

- (BOOL)canGetTrust
{
  nsCOMPtr<nsIX509CertDB> certDB = do_GetService("@mozilla.org/security/x509certdb;1");
  if (!certDB) return NO;

  PRBool trusted;
  // really we are just testing if CERT_GetCertTrust() succeeds. The arguments don't matter.
  nsresult rv = certDB->IsCertTrusted(mCert, nsIX509Cert::CA_CERT, nsIX509CertDB::TRUSTED_SSL, &trusted);
  return NS_SUCCEEDED(rv);
}

- (unsigned int)trustMaskForType:(unsigned int)inType
{
  PRUint32 trustMask = nsIX509CertDB::UNTRUSTED;
  nsCOMPtr<nsIX509CertDB> certDB = do_GetService("@mozilla.org/security/x509certdb;1");
  if (!certDB) return trustMask;

  // sigh, why can't we get these all in one go?
  PRBool trusted;
  if (NS_SUCCEEDED(certDB->IsCertTrusted(mCert, inType, nsIX509CertDB::TRUSTED_SSL, &trusted)) && trusted)
    trustMask |= nsIX509CertDB::TRUSTED_SSL;

  if (NS_SUCCEEDED(certDB->IsCertTrusted(mCert, inType, nsIX509CertDB::TRUSTED_EMAIL, &trusted)) && trusted)
    trustMask |= nsIX509CertDB::TRUSTED_EMAIL;

  if (NS_SUCCEEDED(certDB->IsCertTrusted(mCert, inType, nsIX509CertDB::TRUSTED_OBJSIGN, &trusted)) && trusted)
    trustMask |= nsIX509CertDB::TRUSTED_OBJSIGN;

  return trustMask;
}

- (BOOL)trustedFor:(unsigned int)inUsage asType:(unsigned int)inType
{
  nsCOMPtr<nsIX509CertDB> certDB = do_GetService("@mozilla.org/security/x509certdb;1");
  if (!certDB) return NO;
  
  PRBool trusted;
  nsresult rv = certDB->IsCertTrusted(mCert, inType, inUsage, &trusted);
#if DEBUG
  if (NS_FAILED(rv))
    NSLog(@"IsCertTrusted failed for %@", self);
#endif
  return NS_SUCCEEDED(rv) && trusted;
}

- (BOOL)trustedForSSLAsType:(unsigned int)inType
{
  return [self trustedFor:nsIX509CertDB::TRUSTED_SSL asType:inType];
}

- (BOOL)trustedForEmailAsType:(unsigned int)inType
{
  return [self trustedFor:nsIX509CertDB::TRUSTED_EMAIL asType:inType];
}

- (BOOL)trustedForObjectSigningAsType:(unsigned int)inType
{
  return [self trustedFor:nsIX509CertDB::TRUSTED_OBJSIGN asType:inType];
}

- (void)setTrustedFor:(unsigned int)inUsageMask asType:(unsigned int)inType
{
  unsigned int currentTrustMask = [self trustMaskForType:inType];
  if (currentTrustMask == inUsageMask)
    return;

  nsCOMPtr<nsIX509CertDB> certDB = do_GetService("@mozilla.org/security/x509certdb;1");
  if (!certDB) return;
  certDB->SetCertTrust(mCert, inType, inUsageMask);
  mGotVerification = NO;   // so we fetch it again
  
  [self postChangedNotification];
}

- (void)setTrustedForSSL:(BOOL)inTrustSSL forEmail:(BOOL)inForEmail forObjSigning:(BOOL)inForObjSigning asType:(unsigned int)inType
{
  PRUint32 usageMask = nsIX509CertDB::UNTRUSTED;
  if (inTrustSSL)
    usageMask |= nsIX509CertDB::TRUSTED_SSL;

  if (inForEmail)
    usageMask |= nsIX509CertDB::TRUSTED_EMAIL;

  if (inForObjSigning)
    usageMask |= nsIX509CertDB::TRUSTED_OBJSIGN;

  [self setTrustedFor:usageMask asType:inType];
}

- (void)setDomainIsMismatched:(BOOL)isMismatched
{
  mDomainIsMismatched = isMismatched;
}

- (void)setFallbackProblemMessageKey:(NSString*)problemKey
{
  [mFallbackProblemMessageKey autorelease];
  mFallbackProblemMessageKey = [problemKey copy];
}


- (NSDictionary*)traverseSequence:(nsIASN1Sequence*)inSequence
{
  if (!inSequence) return nil;

  NSMutableDictionary* infoDict = [NSMutableDictionary dictionary];

  nsCOMPtr<nsIMutableArray> objectsArray;
  inSequence->GetASN1Objects(getter_AddRefs(objectsArray));
  if (!objectsArray) return nil;

  PRUint32 numObjects;  
  objectsArray->GetLength(&numObjects);
  for (PRUint32 i = 0; i < numObjects; i ++)
  {
    nsCOMPtr<nsIASN1Object> thisObject;
    objectsArray->QueryElementAt(i, NS_GET_IID(nsIASN1Object),
                                 getter_AddRefs(thisObject));
    if (!thisObject) continue;

    nsAutoString displayName;
    thisObject->GetDisplayName(displayName);
    NSString* displayNameString = [NSString stringWith_nsAString:displayName];

    nsCOMPtr<nsIASN1Sequence> objectAsSequence = do_QueryInterface(thisObject);
    PRBool validContainer;
    if (objectAsSequence && NS_SUCCEEDED(objectAsSequence->GetIsValidContainer(&validContainer)) && validContainer)
    {
      NSDictionary* sequenceDict = [self traverseSequence:objectAsSequence];
      [infoDict setObject:sequenceDict forKey:displayNameString];
    }
    else
    {
      nsAutoString displayValue;
      thisObject->GetDisplayValue(displayValue);
      [infoDict setObject:[NSString stringWith_nsAString:displayValue] forKey:displayNameString];
    }
  }
  
  return infoDict;
}

- (void)ensureASN1Info
{
  if (!mASN1InfoDict)
  {
    nsCOMPtr<nsIASN1Object> asn1Object;
    mCert->GetASN1Structure(getter_AddRefs(asn1Object));
    nsCOMPtr<nsIASN1Sequence> objectAsSequence = do_QueryInterface(asn1Object);
    PRBool validContainer;
    if (objectAsSequence && NS_SUCCEEDED(objectAsSequence->GetIsValidContainer(&validContainer)) && validContainer)
      mASN1InfoDict = [[self traverseSequence:objectAsSequence] retain];
    else
      mASN1InfoDict = [[NSDictionary alloc] init];    // avoid multiple lookups
  }
}

// Get a value from the mASN1InfoDict, using a path of keys from the pipnss.properties string
// bundle, which are mapped to display names. The path is like an xpath.
- (NSString*)ASN1PropertyWithKeyPath:(NSArray*)inKeyPath
{
  [self ensureASN1Info];

  CertificateItemManager* itemManager = [CertificateItemManager sharedCertificateItemManager];

  id infoItem = mASN1InfoDict;
  
  NSEnumerator* pathEnum = [inKeyPath objectEnumerator];
  NSString* curComponent;
  while ((curComponent = [pathEnum nextObject]))
  {
    NSString* displayName = [itemManager valueForStringBundleKey:curComponent];
    if ([displayName length] == 0) return nil;
    
    infoItem = [infoItem objectForKey:displayName];
  }
  
  if (![infoItem isKindOfClass:[NSString class]])
    return nil;

  return (NSString*)infoItem;
}

- (void)postChangedNotification
{
  [[NSNotificationCenter defaultCenter] postNotificationName:kCertificateChangedNotification
                                                      object:self];
}

- (void)certificateChanged:(NSNotification*)inNotification
{
  CertificateItem* changedCert = [inNotification object];
  if ([self certificateIsInParentChain:changedCert])    // actually includes 'self', but that's OK
  {
    mGotVerification = NO;
    PRUint32 oldValidity = mVerification;
    if (oldValidity != [self generalValidity])
    {
      // this is risky to post a notification from a notification callback
      [self performSelector:@selector(postChangedNotification) withObject:nil afterDelay:0];
    }
  }
}

@end

#pragma mark -


class CertificateItemManagerObjects
{
public:
  CertificateItemManagerObjects()
  {
  }
  
  ~CertificateItemManagerObjects()
  {
  }

  nsresult Init()
  {
#define PIPNSS_STRBUNDLE_URL "chrome://pipnss/locale/pipnss.properties"
    nsresult rv;
    nsCOMPtr<nsIStringBundleService> bundleService(do_GetService(NS_STRINGBUNDLE_CONTRACTID, &rv));
    if (NS_FAILED(rv) || !bundleService)
    {
      NSLog(@"Faild to load string bundle %s", PIPNSS_STRBUNDLE_URL);
      return NS_ERROR_FAILURE;
    }
    
    return bundleService->CreateBundle(PIPNSS_STRBUNDLE_URL, getter_AddRefs(mPIPNSSBundle));
  }
  
  NSString* GetStringForBundleKey(NSString* inKey)
  {
    if (!mPIPNSSBundle) return nil;

    nsAutoString keyString;
    [inKey assignTo_nsAString:keyString];
    nsAutoString nameString;
    mPIPNSSBundle->GetStringFromName(keyString.get(), getter_Copies(nameString));
    return [NSString stringWith_nsAString:nameString];
  }

protected:

  nsCOMPtr<nsIStringBundle> mPIPNSSBundle;
};

@implementation CertificateItemManager

+ (CertificateItemManager*)sharedCertificateItemManager
{
  static CertificateItemManager* sSharedCertificateItemManager;
  
  if (!sSharedCertificateItemManager)
    sSharedCertificateItemManager = [[CertificateItemManager alloc] init];

  return sSharedCertificateItemManager;
}

+ (CertificateItem*)certificateItemWithCert:(nsIX509Cert*)inCert
{
  // We could enforce uniqueness here by keeping a dictionary, keyed
  // by the cert's DB key (inCert->GetDbKey()), but no need at
  // present.
  return [CertificateItem certificateItemWithCert:inCert];
}

- (id)init
{
  if ((self = [super init]))
  {
    mDataObjects = new CertificateItemManagerObjects();
    if (NS_FAILED(mDataObjects->Init()))
    {
      NSLog(@"Failed to load pipnss string bundle");
      // should we bail?
    }
  }
  return self;
}

- (void)dealloc
{
  delete mDataObjects;
  [super dealloc];
}

- (NSString*)valueForStringBundleKey:(NSString*)inKey
{
  return mDataObjects->GetStringForBundleKey(inKey);
}

@end

