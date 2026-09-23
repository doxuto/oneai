/**
 * v1 auth trigger — marked explicitly. There is no v2 equivalent for
 * auth.user().onCreate yet (firebase-functions-pro/project-layout).
 */
import * as functionsV1 from "firebase-functions/v1";
import { liveDeps } from "../lib/deps.js";
import { provisionUser } from "./lifecycle.js";

export const onUserCreated = functionsV1
  .region("asia-southeast1")
  .auth.user()
  .onCreate((user) =>
    provisionUser(liveDeps(), { uid: user.uid, email: user.email, displayName: user.displayName, photoURL: user.photoURL }),
  );
