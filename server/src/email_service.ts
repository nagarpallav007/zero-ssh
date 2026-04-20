import nodemailer from 'nodemailer';
import { config } from './config';
import { logger } from './logger';

let transporter: nodemailer.Transporter | null = null;

if (config.smtp) {
  transporter = nodemailer.createTransport({
    host: config.smtp.host,
    port: config.smtp.port,
    secure: config.smtp.port === 465,
    auth: config.smtp.user
      ? { user: config.smtp.user, pass: config.smtp.pass }
      : undefined,
  });
}

export async function sendWorkspaceInvite(opts: {
  toEmail: string;
  workspaceName: string;
  inviterEmail: string;
  token: string;
}) {
  const acceptUrl = `${config.appBaseUrl}/workspaces/accept-invite?token=${opts.token}`;
  const subject = `${opts.inviterEmail} invited you to "${opts.workspaceName}" on ZeroSSH`;
  const text =
    `Hi,\n\n` +
    `${opts.inviterEmail} has invited you to join the workspace "${opts.workspaceName}" on ZeroSSH.\n\n` +
    `Accept the invitation by opening this link in the ZeroSSH app:\n${acceptUrl}\n\n` +
    `This link expires in 7 days.\n\nThe ZeroSSH team`;

  if (!transporter) {
    // No SMTP configured — log to console in development
    logger.info({ toEmail: opts.toEmail, acceptUrl }, 'Workspace invite (no SMTP — logged only)');
    return;
  }

  try {
    await transporter.sendMail({
      from: config.smtp!.from,
      to: opts.toEmail,
      subject,
      text,
    });
  } catch (err) {
    logger.error({ err, toEmail: opts.toEmail }, 'Failed to send invite email');
  }
}
