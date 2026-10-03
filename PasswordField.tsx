import { forwardRef, useState, type InputHTMLAttributes } from 'react'
import { Field } from './Field'

interface PasswordFieldProps extends Omit<InputHTMLAttributes<HTMLInputElement>, 'type'> {
  label: string
  error?: string
  hint?: string
}

export const PasswordField = forwardRef<HTMLInputElement, PasswordFieldProps>(function PasswordField(props, ref) {
  const [visible, setVisible] = useState(false)
  return (
    <Field
      ref={ref}
      ltr
      type={visible ? 'text' : 'password'}
      trailing={
        <button
          type="button"
          onClick={() => setVisible((v) => !v)}
          aria-pressed={visible}
          className="rounded-lg px-3 py-2 text-sm font-semibold text-brand focus-visible:outline focus-visible:outline-2 focus-visible:outline-brand"
        >
          {visible ? 'پنهان' : 'نمایش'}
        </button>
      }
      {...props}
    />
  )
})
