import {readFileSync} from 'node:fs';
import {before, after, beforeEach, test} from 'node:test';
import assert from 'node:assert/strict';
import {initializeTestEnvironment, assertFails, assertSucceeds} from '@firebase/rules-unit-testing';
import {doc, getDoc, setDoc, updateDoc, writeBatch, runTransaction, serverTimestamp, Timestamp} from 'firebase/firestore';

let env;
const code = 'a'.repeat(32), ownerCode = 'o'.repeat(32);
const newGroup = () => ({name:'Kona', createdBy:'owner', createdAt:serverTimestamp(),
  timeZone:'America/Vancouver', activeTripId:null, lastOdometer:null, schedule:{},
  spliitGroupId:'',spliitName:'',spliitMembers:[],spliitMemberIds:[],ownerMemberId:''});
before(async () => {
  env = await initializeTestEnvironment({projectId:'demo-kona-share', firestore:{
    host:'127.0.0.1',port:8080,rules:readFileSync(new URL('../firestore.rules',import.meta.url),'utf8')}});
});
after(async () => { await env?.cleanup(); });
beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async c => {
    const db = c.firestore();
    await setDoc(doc(db,'groups/g'),newGroup());
    for (const [uid,role] of [['owner','owner'],['owner2','owner'],['borrower','borrower']]) {
      await setDoc(doc(db,`groups/g/members/${uid}`),{uid,name:uid,role,spliitMemberId:''});
      await setDoc(doc(db,`users/${uid}`),{name:uid,groupId:'g'});
    }
    await setDoc(doc(db,`invites/${code}`),{groupId:'g',role:'borrower'});
    await setDoc(doc(db,`invites/${ownerCode}`),{groupId:'g',role:'owner'});
    await setDoc(doc(db,'groups/g/private/invites'),{ownerCode,borrowerCode:code});
    const at = Date.now()+3600000;
    for (const id of ['a','b']) await setDoc(doc(db,`groups/g/bookings/${id}`),{
      userId:'borrower',driver:'borrower',startAt:Timestamp.fromMillis(at),endAt:Timestamp.fromMillis(at+7200000),
      estimatedKm:30,note:'Errands',status:'requested',decisionNote:'',createdAt:Timestamp.now()});
  });
});
const dbFor = uid => env.authenticatedContext(uid).firestore();
test('nonmembers cannot read groups, members or trips',async () => {
  const db = dbFor('stranger');
  await assertFails(getDoc(doc(db,'groups/g')));
  await assertFails(getDoc(doc(db,'groups/g/members/owner')));
  await assertFails(getDoc(doc(db,'groups/g/trips/private')));
});
test('borrowers cannot promote themselves, change rates/config, or approve',async () => {
  const db = dbFor('borrower');
  await assertFails(updateDoc(doc(db,'groups/g/members/borrower'),{role:'owner'}));
  await assertFails(updateDoc(doc(db,'groups/g'),{spliitGroupId:'stolen'}));
  await assertFails(updateDoc(doc(db,'groups/g/bookings/a'),{status:'approved'}));
  await assertFails(getDoc(doc(db,'groups/g/private/invites')));
});
test('borrowers cannot mint owner invitations',async () => {
  await assertFails(setDoc(doc(dbFor('borrower'),`invites/${'x'.repeat(32)}`),{groupId:'g',role:'owner'}));
});
test('borrower invite cannot grant owner role; valid borrower join succeeds',async () => {
  const db = dbFor('new');
  await setDoc(doc(db,'users/new'),{name:'New',groupId:null});
  function join(role) {
    const batch = writeBatch(db);
    batch.set(doc(db,'joinProofs/new'),{groupId:'g',code});
    batch.set(doc(db,'groups/g/members/new'),{uid:'new',name:'New',role,spliitMemberId:''});
    batch.update(doc(db,'users/new'),{groupId:'g'});
    return batch.commit();
  }
  await assertFails(join('owner'));
  await assertSucceeds(join('borrower'));
});
test('an owner invitation grants owner role',async () => {
  const db = dbFor('newowner');
  await setDoc(doc(db,'users/newowner'),{name:'New owner',groupId:null});
  const batch = writeBatch(db);
  batch.set(doc(db,'joinProofs/newowner'),{groupId:'g',code:ownerCode});
  batch.set(doc(db,'groups/g/members/newowner'),{uid:'newowner',name:'New owner',role:'owner',spliitMemberId:''});
  batch.update(doc(db,'users/newowner'),{groupId:'g'});
  await assertSucceeds(batch.commit());
  await assertSucceeds(getDoc(doc(db,'groups/g/private/invites')));
});
test('new group creator becomes owner atomically',async () => {
  const db = dbFor('creator');
  await setDoc(doc(db,'users/creator'),{name:'Creator',groupId:null});
  const batch = writeBatch(db);
  batch.set(doc(db,'groups/new'),{...newGroup(),createdBy:'creator'});
  batch.set(doc(db,'groups/new/members/creator'),{uid:'creator',name:'Creator',role:'owner',spliitMemberId:''});
  batch.update(doc(db,'users/creator'),{groupId:'new'});
  batch.set(doc(db,`invites/${'n'.repeat(32)}`),{groupId:'new',role:'owner'});
  batch.set(doc(db,'groups/new/private/invites'),{ownerCode:'n'.repeat(32),borrowerCode:'m'.repeat(32)});
  await assertSucceeds(batch.commit());
});
test('concurrent owner approvals cannot book the same time twice',async () => {
  async function approve(uid,id) {
    const db = dbFor(uid), g = doc(db,'groups/g'), b = doc(db,`groups/g/bookings/${id}`);
    return runTransaction(db,async tx => {
      const group = (await tx.get(g)).data(), booking = (await tx.get(b)).data();
      const schedule = {...group.schedule};
      const start=booking.startAt.toMillis(),end=booking.endAt.toMillis();
      for (const slot of Object.values(schedule)) {
        if (start < slot.end && end > slot.start) throw Error('overlap');
      }
      schedule[id]={start,end};tx.update(g,{schedule});tx.update(b,{status:'approved'});
    });
  }
  const results = await Promise.allSettled([approve('owner','a'),approve('owner2','b')]);
  assert.equal(results.filter(r => r.status==='fulfilled').length,1);
  assert.equal(results.filter(r => r.status==='rejected').length,1);
});
test('approved borrower can start and finish; odometer cannot go backwards',async () => {
  await env.withSecurityRulesDisabled(async c => { await updateDoc(doc(c.firestore(),'groups/g/bookings/a'), {status:'approved',startAt:Timestamp.fromMillis(Date.now()-60000)}); });
  const db = dbFor('borrower');
  const batch = writeBatch(db);
  batch.set(doc(db,'groups/g/trips/t'),{userId:'borrower',driver:'borrower',bookingId:'a',
    startAt:serverTimestamp(),startKm:42000,endAt:null,endKm:null,status:'active',sync:'local',expenseId:'',remoteGroupId:'',payerId:'',borrowerId:''});
  batch.update(doc(db,'groups/g/bookings/a'),{status:'active'});
  batch.update(doc(db,'groups/g'),{activeTripId:'t'});
  await assertSucceeds(batch.commit());
  const finish = km => {
    const b=writeBatch(db);
    b.update(doc(db,'groups/g/trips/t'),{status:'completed',endAt:Timestamp.now(),endKm:km});
    b.update(doc(db,'groups/g/bookings/a'),{status:'completed'});
    b.update(doc(db,'groups/g'),{activeTripId:null,lastOdometer:km,schedule:{}});
    return b.commit();
  };
  await assertFails(finish(41999));
  await assertSucceeds(finish(42030));
  await assertFails(updateDoc(doc(db,'groups/g/trips/t'),{startKm:0}));
});

test('Spliit participants cannot be stolen or set to the owner payer', async () => {
  await updateDoc(doc(dbFor('owner'),'groups/g'),{
    spliitGroupId:'remote',spliitName:'Our group',ownerMemberId:'payer',
    spliitMembers:[{id:'payer',name:'Owners'},{id:'alex',name:'Alex'},{id:'sam',name:'Sam'}],
    spliitMemberIds:['payer','alex','sam']});
  const db = dbFor('borrower');
  const claim = (remoteId, user='borrower') => {
    const db = dbFor(user), b=writeBatch(db);
    b.set(doc(db,`groups/g/spliitClaims/${remoteId}`),{uid:user});
    b.update(doc(db,`groups/g/members/${user}`),{spliitMemberId:remoteId});
    return b.commit();
  };
  await assertFails(claim('payer'));
  await assertSucceeds(claim('alex'));
  await assertFails(claim('alex','owner2'));
  await assertFails(updateDoc(doc(db,'groups/g/members/borrower'),{spliitMemberId:'sam'}));
});


test('a borrower cannot start a future booking early', async () => {
  await updateDoc(doc(dbFor('owner'),'groups/g/bookings/a'),{status:'approved'});
  const db=dbFor('borrower'),b=writeBatch(db);
  b.set(doc(db,'groups/g/trips/early'),{userId:'borrower',driver:'borrower',bookingId:'a',startAt:serverTimestamp(),startKm:42000,endAt:null,endKm:null,status:'active',sync:'local',expenseId:'',remoteGroupId:'',payerId:'',borrowerId:''});
  b.update(doc(db,'groups/g/bookings/a'),{status:'active'});
  b.update(doc(db,'groups/g'),{activeTripId:'early'});
  await assertFails(b.commit());
});
